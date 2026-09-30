/* UIKit controls feed a standard SDL gamepad. The first hardware controller
   shares player one with touch; additional hardware controllers keep their ports.

   Aiming works the way it does in other mobile shooters: drag anywhere on the
   right of the screen, or drag FIRE while holding it, and the view turns with
   the finger. The motion is sent as relative mouse movement, which the game
   adds straight to the player's facing (halo_linux_mouse_look in
   port/linux/src/xinput_sdl.c), so it has no stick dead zone, turn-rate cap or
   ramp-up, and it slows down with the zoom level. The left of the screen is a
   floating move stick. Every control can be moved, resized, hidden and given
   another icon in the editor (host_touch_editor.m); the layout and settings
   are kept in Documents/controls.json. */
#import <UIKit/UIKit.h>
#include <SDL3/SDL.h>
#include "ios_host.h"
#import "host_orientation.h"
#import "host_touch.h"
#include <math.h>

static SDL_Joystick *touch_joystick;
static SDL_JoystickID touch_id, primary_hardware;

/* The game ignores less than 9000/32767 of deflection on each stick axis
   (GAMEPAD_STICK_DEAD_RANGE, source/input/input_xbox.c). Touch sticks start
   just past it, so the smallest push already moves. */
static const float game_dead_range=9000.0f/32767.0f;
/* Finger travel below this fraction of a stick's radius does nothing, so a
   resting thumb does not drift. */
static const CGFloat touch_dead_zone=.1;
/* Points of finger travel to the game's mouse units (0.0022 radians each):
   about half a turn for a swipe across an iPhone at sensitivity 1. */
static const float look_points_to_mouse=1.6f;
/* How much of the screen's width, from the left, starts the move stick. */
static const CGFloat move_zone_fraction=.42;

static void button_state(int button, BOOL down) {
    if(touch_joystick) SDL_SetJoystickVirtualButton(touch_joystick,button,down);
}
static void axis_state(int axis, float value) {
    if(touch_joystick) SDL_SetJoystickVirtualAxis(touch_joystick,axis,(Sint16)(fmaxf(-1,fminf(1,value))*32767));
}
/* A stick axis from -1…1 of intended movement to the value that gives the
   game that movement after its dead zone. */
static float stick_value(CGFloat value) {
    if(value==0) return 0;
    float magnitude=fminf(1,fabsf((float)value));
    return copysignf(game_dead_range+(1-game_dead_range)*magnitude,(float)value);
}
static void push_look(CGFloat dx, CGFloat dy) {
    if(dx==0 && dy==0) return;
    HaloTouchSettings *settings=HaloTouchSettings.shared;
    float scale=look_points_to_mouse*(float)settings.lookSensitivity;
    SDL_Event event;
    SDL_zero(event);
    event.type=SDL_EVENT_MOUSE_MOTION;
    event.motion.timestamp=SDL_GetTicksNS();
    event.motion.xrel=(float)dx*scale;
    event.motion.yrel=(float)dy*scale*(settings.invertLook?-1:1);
    SDL_PushEvent(&event);
}

/* The game rumbles player one's controller, which is the touch controller:
   play it on the phone, and on a hardware controller sharing the port. */
static bool SDLCALL touch_rumble(void *userdata, Uint16 low, Uint16 high) {
    (void)userdata;
    host_ios_haptics_rumble((float)MAX(low,high)/65535.0f);
    if(primary_hardware) {
        SDL_Gamepad *pad=SDL_GetGamepadFromID(primary_hardware);
        if(pad) SDL_RumbleGamepad(pad,low,high,250);
    }
    return true;
}

void host_ios_touch_initialize(void) {
    SDL_VirtualJoystickDesc desc;
    SDL_INIT_INTERFACE(&desc);
    desc.type=SDL_JOYSTICK_TYPE_GAMEPAD;
    desc.naxes=SDL_GAMEPAD_AXIS_COUNT;
    desc.nbuttons=SDL_GAMEPAD_BUTTON_COUNT;
    desc.axis_mask=(1u<<SDL_GAMEPAD_AXIS_COUNT)-1;
    desc.button_mask=(1u<<SDL_GAMEPAD_BUTTON_COUNT)-1;
    desc.name="Halo Touch Controls";
    desc.Rumble=touch_rumble;
    touch_id=SDL_AttachVirtualJoystick(&desc);
    touch_joystick=SDL_OpenJoystick(touch_id);
    if(!touch_joystick)host_fatal("Could not initialize touch controls: %s",SDL_GetError());
    axis_state(SDL_GAMEPAD_AXIS_LEFT_TRIGGER,-1);
    axis_state(SDL_GAMEPAD_AXIS_RIGHT_TRIGGER,-1);
    /* SDL's view controller reads this when the game creates its window. */
    host_ios_apply_exit_gesture();
}
int host_ios_gamepads(uint32_t *out,int capacity) {
    int count=0,used=0;SDL_JoystickID *ids=SDL_GetGamepads(&count);
    primary_hardware=0;
    if(capacity>0 && touch_id)out[used++]=touch_id;
    for(int i=0;i<count;i++) {
        if(ids[i]==touch_id)continue;
        if(!primary_hardware) {
            primary_hardware=ids[i];
            if(!SDL_GetGamepadFromID(ids[i]))SDL_OpenGamepad(ids[i]);
        } else if(used<capacity) out[used++]=ids[i];
    }
    SDL_free(ids);return used;
}
int host_ios_gamepad_type(SDL_Gamepad *pad) {
    /* Keep the shared touch/hardware controller in the first recognized port. */
    return SDL_GetGamepadID(pad)==touch_id?SDL_GAMEPAD_TYPE_XBOX360:SDL_GetGamepadType(pad);
}
int host_ios_gamepad_axis(SDL_Gamepad *pad,int axis) {
    int value=SDL_GetGamepadAxis(pad,axis);
    if(SDL_GetGamepadID(pad)==touch_id && primary_hardware) {
        int physical=SDL_GetGamepadAxis(SDL_GetGamepadFromID(primary_hardware),axis);
        if(abs(physical)>abs(value))value=physical;
    }
    return value;
}
int host_ios_gamepad_button(SDL_Gamepad *pad,int button) {
    return SDL_GetGamepadButton(pad,button) ||
        (SDL_GetGamepadID(pad)==touch_id && primary_hardware &&
         SDL_GetGamepadButton(SDL_GetGamepadFromID(primary_hardware),button));
}
void host_ios_touch_reset(void) {
    for(int i=0;i<SDL_GAMEPAD_BUTTON_COUNT;i++)button_state(i,NO);
    for(int i=0;i<SDL_GAMEPAD_AXIS_COUNT;i++)axis_state(i,i>=SDL_GAMEPAD_AXIS_LEFT_TRIGGER?-1:0);
}
void host_ios_apply_exit_gesture(void) {
    /* 1: the home indicator fades out and one swipe up leaves, as in other
       apps. 2 (SDL's default for a fullscreen window) makes the first swipe
       only reveal the indicator. */
    SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR,HaloTouchSettings.shared.protectExit?"2":"1");
}

/* ---------- the controls and their defaults */

const HaloControlSpec halo_control_specs[HaloControlCount]={
    {"move","Move stick","MOVE",NULL,"Move",HaloControlKindStick,SDL_GAMEPAD_AXIS_LEFTX,150,HaloAnchorBottomLeft,100,100,NO,NO,""},
    {"look","Look stick","LOOK",NULL,"Look",HaloControlKindStick,SDL_GAMEPAD_AXIS_RIGHTX,140,HaloAnchorBottomRight,240,96,YES,NO,""},
    {"fire","Fire","FIRE",NULL,"Fire",HaloControlKindTrigger,SDL_GAMEPAD_AXIS_RIGHT_TRIGGER,78,HaloAnchorBottomRight,62,210,NO,YES,
        "target,scope,flame.fill,bolt.fill,smallcircle.filled.circle"},
    {"grenade","Grenade","GRENADE",NULL,"Throw grenade",HaloControlKindTrigger,SDL_GAMEPAD_AXIS_LEFT_TRIGGER,60,HaloAnchorBottomLeft,50,212,NO,NO,
        "burst.fill,circle.hexagongrid.fill,sparkle,flame.fill"},
    {"jump","Jump / Select","A","A","A, jump or select",HaloControlKindButton,SDL_GAMEPAD_BUTTON_SOUTH,64,HaloAnchorBottomRight,46,48,NO,NO,
        "arrow.up.to.line,arrow.up,chevron.up,hare.fill"},
    {"melee","Melee / Back","B","B","B, melee or back",HaloControlKindButton,SDL_GAMEPAD_BUTTON_EAST,54,HaloAnchorBottomRight,116,104,NO,NO,
        "hand.raised.fill,bolt.fill,burst,xmark"},
    {"reload","Reload / Use","X","X","X, reload or use",HaloControlKindButton,SDL_GAMEPAD_BUTTON_WEST,54,HaloAnchorBottomRight,44,124,NO,NO,
        "arrow.triangle.2.circlepath,arrow.clockwise,hand.tap.fill"},
    {"weapon","Switch weapon","Y","Y","Y, switch weapon",HaloControlKindButton,SDL_GAMEPAD_BUTTON_NORTH,52,HaloAnchorBottomRight,46,286,NO,NO,
        "arrow.left.arrow.right,arrow.2.squarepath,rectangle.2.swap"},
    {"crouch","Crouch","CROUCH",NULL,"Crouch",HaloControlKindButton,SDL_GAMEPAD_BUTTON_LEFT_STICK,52,HaloAnchorBottomRight,124,36,NO,NO,
        "arrow.down.to.line,chevron.down,arrow.down"},
    {"zoom","Zoom","ZOOM",NULL,"Zoom",HaloControlKindButton,SDL_GAMEPAD_BUTTON_RIGHT_STICK,52,HaloAnchorBottomRight,142,180,NO,NO,
        "plus.magnifyingglass,scope,binoculars.fill,eye.fill"},
    {"flashlight","Flashlight","LIGHT",NULL,"Flashlight",HaloControlKindButton,SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER,44,HaloAnchorBottomRight,134,264,NO,NO,
        "flashlight.on.fill,lightbulb.fill,sun.max.fill"},
    {"swapgrenade","Switch grenade","SWAP G",NULL,"Switch grenade",HaloControlKindButton,SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,44,HaloAnchorBottomLeft,122,222,NO,NO,
        "arrow.2.squarepath,arrow.triangle.swap,repeat"},
    {"pause","Pause / Start","PAUSE",NULL,"Pause or start",HaloControlKindButton,SDL_GAMEPAD_BUTTON_START,40,HaloAnchorTopCenter,0,20,NO,NO,
        "pause.fill,line.3.horizontal,list.bullet"},
    {"back","Back / Scores","BACK",NULL,"Back or scoreboard",HaloControlKindButton,SDL_GAMEPAD_BUTTON_BACK,40,HaloAnchorTopCenter,-56,20,YES,NO,
        "list.number,chevron.backward,person.3.fill"},
    {"up","Menu up","↑",NULL,"Menu up",HaloControlKindButton,SDL_GAMEPAD_BUTTON_DPAD_UP,32,HaloAnchorTopLeft,52,18,NO,NO,
        "chevron.up,arrowtriangle.up.fill,arrow.up"},
    {"down","Menu down","↓",NULL,"Menu down",HaloControlKindButton,SDL_GAMEPAD_BUTTON_DPAD_DOWN,32,HaloAnchorTopLeft,52,86,NO,NO,
        "chevron.down,arrowtriangle.down.fill,arrow.down"},
    {"left","Menu left","←",NULL,"Menu left",HaloControlKindButton,SDL_GAMEPAD_BUTTON_DPAD_LEFT,32,HaloAnchorTopLeft,18,52,NO,NO,
        "chevron.left,arrowtriangle.left.fill,arrow.left"},
    {"right","Menu right","→",NULL,"Menu right",HaloControlKindButton,SDL_GAMEPAD_BUTTON_DPAD_RIGHT,32,HaloAnchorTopLeft,86,52,NO,NO,
        "chevron.right,arrowtriangle.right.fill,arrow.right"},
};

NSArray<NSString *> *halo_control_icons(int index) {
    NSString *list=@(halo_control_specs[index].icons);
    if(!list.length) return @[];
    return [list componentsSeparatedByString:@","];
}

/* ---------- settings, kept in Documents/controls.json */

@implementation HaloControlState
@end

static double json_number(id value,double fallback,double low,double high) {
    if(![value isKindOfClass:NSNumber.class]) return fallback;
    double number=[value doubleValue];
    if(!isfinite(number)) return fallback;
    return fmin(high,fmax(low,number));
}
static BOOL json_bool(id value,BOOL fallback) {
    return [value isKindOfClass:NSNumber.class]?[value boolValue]:fallback;
}

@interface HaloTouchSettings ()
@property(nonatomic, strong) NSMutableArray<HaloControlState *> *mutableControls;
@end

@implementation HaloTouchSettings
+ (instancetype)shared {
    static HaloTouchSettings *settings;
    static dispatch_once_t once;
    dispatch_once(&once,^{settings=[[HaloTouchSettings alloc] init];});
    return settings;
}
- (instancetype)init {
    if(!(self=[super init])) return nil;
    self.lookSensitivity=1;self.opacity=.8;self.invertLook=NO;self.floatingStick=YES;
    self.haptics=YES;self.showNames=NO;self.protectExit=NO;
    [self resetLayout];
    [self load];
    return self;
}
- (NSArray<HaloControlState *> *)controls {return self.mutableControls;}
- (NSString *)documents {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
}
- (NSString *)path {return [self.documents stringByAppendingPathComponent:@"controls.json"];}
- (NSString *)customIconPath:(int)index {
    NSString *name=[@(halo_control_specs[index].ident) stringByAppendingPathExtension:@"png"];
    return [[self.documents stringByAppendingPathComponent:@"Controls"] stringByAppendingPathComponent:name];
}
- (void)resetLayout {
    self.mutableControls=[NSMutableArray arrayWithCapacity:HaloControlCount];
    for(int i=0;i<HaloControlCount;i++) {
        const HaloControlSpec *spec=&halo_control_specs[i];
        HaloControlState *state=[HaloControlState new];
        state.scale=1;state.hidden=spec->hidden;state.aim=spec->aim;
        NSArray<NSString *> *icons=halo_control_icons(i);
        state.icon=icons.count?[@"sf:" stringByAppendingString:icons.firstObject]:@"text";
        [self.mutableControls addObject:state];
    }
}
- (void)load {
    NSData *data=[NSData dataWithContentsOfFile:self.path];
    if(!data) return;
    id root=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if(![root isKindOfClass:NSDictionary.class]) {
        host_logf(HOST_LOG_WARN,"controls.json is not readable; using the default controls");
        return;
    }
    NSDictionary *settings=root[@"settings"];
    if([settings isKindOfClass:NSDictionary.class]) {
        self.lookSensitivity=json_number(settings[@"look_sensitivity"],self.lookSensitivity,.1,5);
        self.opacity=json_number(settings[@"opacity"],self.opacity,.15,1);
        self.invertLook=json_bool(settings[@"invert_look"],self.invertLook);
        self.floatingStick=json_bool(settings[@"floating_stick"],self.floatingStick);
        self.haptics=json_bool(settings[@"haptics"],self.haptics);
        self.showNames=json_bool(settings[@"show_names"],self.showNames);
        self.protectExit=json_bool(settings[@"swipe_twice_to_exit"],self.protectExit);
    }
    NSDictionary *controls=root[@"controls"];
    if(![controls isKindOfClass:NSDictionary.class]) return;
    for(int i=0;i<HaloControlCount;i++) {
        NSDictionary *entry=controls[@(halo_control_specs[i].ident)];
        if(![entry isKindOfClass:NSDictionary.class]) continue;
        HaloControlState *state=self.mutableControls[i];
        state.placed=json_bool(entry[@"placed"],NO);
        state.x=json_number(entry[@"x"],.5,0,1);
        state.y=json_number(entry[@"y"],.5,0,1);
        state.scale=json_number(entry[@"scale"],1,.5,2);
        state.hidden=json_bool(entry[@"hidden"],state.hidden);
        state.aim=json_bool(entry[@"aim_while_held"],state.aim);
        NSString *icon=entry[@"icon"];
        if([icon isKindOfClass:NSString.class] && ([icon hasPrefix:@"sf:"] || [icon isEqualToString:@"text"] || [icon isEqualToString:@"custom"]))
            state.icon=icon;
    }
}
- (void)save {
    NSMutableDictionary *controls=[NSMutableDictionary dictionary];
    for(int i=0;i<HaloControlCount;i++) {
        HaloControlState *state=self.mutableControls[i];
        controls[@(halo_control_specs[i].ident)]=@{
            @"placed":@(state.placed),@"x":@(state.x),@"y":@(state.y),@"scale":@(state.scale),
            @"hidden":@(state.hidden),@"aim_while_held":@(state.aim),@"icon":state.icon,
        };
    }
    NSDictionary *root=@{
        @"version":@1,
        @"settings":@{
            @"look_sensitivity":@(self.lookSensitivity),@"opacity":@(self.opacity),
            @"invert_look":@(self.invertLook),@"floating_stick":@(self.floatingStick),
            @"haptics":@(self.haptics),@"show_names":@(self.showNames),
            @"swipe_twice_to_exit":@(self.protectExit),
        },
        @"controls":controls,
    };
    NSError *error=nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if(!data || ![data writeToFile:self.path options:NSDataWritingAtomic error:&error])
        host_logf(HOST_LOG_WARN,"could not save controls.json: %s",error.localizedDescription.UTF8String);
}
- (UIImage *)imageForControl:(int)index pointSize:(CGFloat)pointSize {
    NSString *icon=self.mutableControls[index].icon;
    if([icon isEqualToString:@"custom"]) return [UIImage imageWithContentsOfFile:[self customIconPath:index]];
    if([icon hasPrefix:@"sf:"]) {
        UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
        return [UIImage systemImageNamed:[icon substringFromIndex:3] withConfiguration:configuration];
    }
    return nil;
}
@end

/* ---------- a button */

static UIColor *badge_color(const char *badge) {
    switch(badge?badge[0]:0) {
    case 'A': return [UIColor colorWithRed:.45 green:.85 blue:.35 alpha:1];
    case 'B': return [UIColor colorWithRed:.95 green:.35 blue:.3 alpha:1];
    case 'X': return [UIColor colorWithRed:.3 green:.6 blue:1 alpha:1];
    case 'Y': return [UIColor colorWithRed:1 green:.8 blue:.2 alpha:1];
    default: return UIColor.whiteColor;
    }
}

@interface HaloButton : UIControl
@property(nonatomic) int index;
@property(nonatomic) BOOL pressed;
@property(nonatomic) CGPoint lastAim;
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) UILabel *badgeLabel;
@property(nonatomic, strong) UILabel *nameLabel;
@end

@implementation HaloButton
- (instancetype)initWithIndex:(int)index {
    if(!(self=[super initWithFrame:CGRectMake(0,0,44,44)])) return nil;
    const HaloControlSpec *spec=&halo_control_specs[index];
    self.index=index;
    self.exclusiveTouch=NO;
    self.isAccessibilityElement=YES;
    self.accessibilityLabel=@(spec->accessibility);
    self.accessibilityTraits=UIAccessibilityTraitButton;
    self.layer.borderWidth=1.25;
    self.iconView=[UIImageView new];
    self.iconView.contentMode=UIViewContentModeScaleAspectFit;
    self.iconView.tintColor=UIColor.whiteColor;
    self.iconView.userInteractionEnabled=NO;
    [self addSubview:self.iconView];
    self.label=[UILabel new];
    self.label.textColor=UIColor.whiteColor;
    self.label.textAlignment=NSTextAlignmentCenter;
    self.label.adjustsFontSizeToFitWidth=YES;
    self.label.minimumScaleFactor=.5;
    self.label.text=@(spec->text);
    [self addSubview:self.label];
    self.badgeLabel=[UILabel new];
    self.badgeLabel.textAlignment=NSTextAlignmentCenter;
    self.badgeLabel.text=spec->badge?@(spec->badge):nil;
    self.badgeLabel.textColor=badge_color(spec->badge);
    [self addSubview:self.badgeLabel];
    self.nameLabel=[UILabel new];
    self.nameLabel.textAlignment=NSTextAlignmentCenter;
    self.nameLabel.textColor=[UIColor colorWithWhite:1 alpha:.85];
    self.nameLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    self.nameLabel.text=@(spec->text).uppercaseString;
    self.nameLabel.layer.shadowColor=UIColor.blackColor.CGColor;
    self.nameLabel.layer.shadowOpacity=.8f;
    self.nameLabel.layer.shadowRadius=2;
    self.nameLabel.layer.shadowOffset=CGSizeZero;
    [self addSubview:self.nameLabel];
    [self applySettings];
    return self;
}
- (void)applySettings {
    HaloTouchSettings *settings=HaloTouchSettings.shared;
    CGFloat size=self.bounds.size.width;
    UIImage *image=[settings imageForControl:self.index pointSize:size*.36];
    BOOL custom=[settings.controls[self.index].icon isEqualToString:@"custom"];
    self.iconView.image=custom?[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]:image;
    self.iconView.hidden=image==nil;
    self.label.hidden=image!=nil;
    self.badgeLabel.hidden=image==nil || !self.badgeLabel.text.length;
    self.nameLabel.hidden=!settings.showNames;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat size=self.bounds.size.width;
    self.layer.cornerRadius=size/2;
    BOOL custom=[HaloTouchSettings.shared.controls[self.index].icon isEqualToString:@"custom"];
    CGFloat inset=size*(custom?.17:.22);
    CGRect icon=CGRectInset(self.bounds,inset,inset);
    if(self.badgeLabel.text.length && !custom) icon=CGRectOffset(icon,0,-size*.05);
    self.iconView.frame=icon;
    self.label.frame=CGRectInset(self.bounds,size*.1,size*.2);
    self.label.font=[UIFont systemFontOfSize:MAX(9,size*(self.label.text.length>2?.2:.36)) weight:UIFontWeightBold];
    self.badgeLabel.font=[UIFont systemFontOfSize:MAX(8,size*.16) weight:UIFontWeightHeavy];
    self.badgeLabel.frame=CGRectMake(0,size*.72,size,size*.2);
    self.nameLabel.frame=CGRectMake(-24,size+2,size+48,13);
    [self updateAppearance];
}
- (void)updateAppearance {
    self.backgroundColor=self.pressed?[UIColor colorWithWhite:1 alpha:.32]:[UIColor colorWithWhite:0 alpha:.3];
    self.layer.borderColor=[UIColor colorWithWhite:1 alpha:self.pressed?.95:.5].CGColor;
    self.transform=self.pressed?CGAffineTransformMakeScale(.9,.9):CGAffineTransformIdentity;
}
- (void)sendDown:(BOOL)down {
    const HaloControlSpec *spec=&halo_control_specs[self.index];
    if(spec->kind==HaloControlKindTrigger) axis_state(spec->input,down?1:-1);
    else button_state(spec->input,down);
    if(down && !self.pressed && self.index!=HaloControlFire) host_ios_haptics_tap();
    self.pressed=down;
    [UIView animateWithDuration:down?.05:.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
        animations:^{[self updateAppearance];} completion:nil];
}
- (void)releaseInput {
    if(self.pressed) [self sendDown:NO];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super beginTrackingWithTouch:touch withEvent:event];
    self.lastAim=[touch locationInView:nil];
    [self sendDown:YES];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super continueTrackingWithTouch:touch withEvent:event];
    CGPoint point=[touch locationInView:nil];
    if(HaloTouchSettings.shared.controls[self.index].aim) push_look(point.x-self.lastAim.x,point.y-self.lastAim.y);
    self.lastAim=point;
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [super endTrackingWithTouch:touch withEvent:event];[self sendDown:NO];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [super cancelTrackingWithEvent:event];[self sendDown:NO];
}
- (BOOL)accessibilityActivate {
    [self sendDown:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self sendDown:NO];});
    return YES;
}
@end

/* ---------- a stick (drawn here; its touches are handled by HaloControls) */

@interface HaloStickView : UIView
@property(nonatomic) CGPoint knob;     /* -1…1 on each axis */
@property(nonatomic) BOOL active;
@property(nonatomic, copy) NSString *caption;
@end

@implementation HaloStickView
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame])) return nil;
    self.backgroundColor=UIColor.clearColor;
    self.opaque=NO;
    self.userInteractionEnabled=NO;
    self.contentMode=UIViewContentModeRedraw;
    return self;
}
- (void)setKnob:(CGPoint)knob {_knob=knob;[self setNeedsDisplay];}
- (void)setActive:(BOOL)active {_active=active;[self setNeedsDisplay];}
- (CGFloat)travel {return self.bounds.size.width*.34;}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGFloat size=self.bounds.size.width;
    UIBezierPath *base=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds,1.5,1.5)];
    [[UIColor colorWithWhite:0 alpha:self.active?.26:.16] setFill];
    [base fill];
    [[UIColor colorWithWhite:1 alpha:self.active?.7:.4] setStroke];
    base.lineWidth=1.5;
    [base stroke];
    CGFloat knob=size*.4,travel=self.travel;
    CGRect knobRect=CGRectMake(size/2+self.knob.x*travel-knob/2,size/2+self.knob.y*travel-knob/2,knob,knob);
    [[UIColor colorWithWhite:1 alpha:self.active?.5:.28] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:knobRect] fill];
    if(self.caption.length && !self.active) {
        NSDictionary *attributes=@{NSFontAttributeName:[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:.75]};
        CGSize text=[self.caption sizeWithAttributes:attributes];
        [self.caption drawAtPoint:CGPointMake((size-text.width)/2,size-text.height-size*.08) withAttributes:attributes];
    }
}
@end

/* ---------- the overlay */

@interface HaloControls ()
@property(nonatomic, weak, readwrite) HaloControlEditor *editor;
@property(nonatomic, strong) NSMutableArray<UIView *> *controlViews;
@property(nonatomic, strong) HaloStickView *moveStick;
@property(nonatomic, strong) HaloStickView *lookStick;
@property(nonatomic, strong) UIButton *hideButton;
@property(nonatomic, strong) UIButton *editButton;
@property(nonatomic) BOOL controlsHidden;
@property(nonatomic, strong) UITouch *moveTouch;
@property(nonatomic, strong) UITouch *lookTouch;
@property(nonatomic, strong) UITouch *lookStickTouch;
@property(nonatomic) CGPoint moveBase;
@property(nonatomic) CGPoint lookLast;
@end

@implementation HaloControls
- (UIButton *)chromeButton:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:configuration] forState:UIControlStateNormal];
    button.tintColor=UIColor.whiteColor;
    button.backgroundColor=[UIColor colorWithWhite:0 alpha:.3];
    button.layer.cornerRadius=18;
    button.accessibilityLabel=label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:button];
    return button;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.multipleTouchEnabled=YES;
    self.controlViews=[NSMutableArray arrayWithCapacity:HaloControlCount];
    for(int i=0;i<HaloControlCount;i++) {
        const HaloControlSpec *spec=&halo_control_specs[i];
        UIView *view;
        if(spec->kind==HaloControlKindStick) {
            HaloStickView *stick=[[HaloStickView alloc] initWithFrame:CGRectMake(0,0,140,140)];
            stick.caption=@(spec->text);
            stick.isAccessibilityElement=YES;
            stick.accessibilityLabel=@(spec->accessibility);
            if(i==HaloControlMove) self.moveStick=stick; else self.lookStick=stick;
            view=stick;
        } else {
            view=[[HaloButton alloc] initWithIndex:i];
        }
        [self.controlViews addObject:view];
        [self addSubview:view];
    }
    self.hideButton=[self chromeButton:@"eye.slash" label:@"Hide controls" action:@selector(toggleControls)];
    self.editButton=[self chromeButton:@"slider.horizontal.3" label:@"Customize controls" action:@selector(beginEditing)];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(reset) name:UIApplicationWillResignActiveNotification object:nil];
    [self applySettings];
    return self;
}
- (UIView *)viewForControl:(int)index {return self.controlViews[index];}
- (CGRect)layoutRect {
    CGRect safe=UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets);
    return UIEdgeInsetsInsetRect(safe,UIEdgeInsetsMake(8,12,8,12));
}
- (CGFloat)layoutScale {
    return MIN(1.5,MAX(1.0,[self layoutRect].size.height/390.0));
}
- (CGFloat)diameterForControl:(int)index {
    return halo_control_specs[index].size*[self layoutScale]*HaloTouchSettings.shared.controls[index].scale;
}
- (CGPoint)centerForControl:(int)index {
    CGRect r=[self layoutRect];
    HaloControlState *state=HaloTouchSettings.shared.controls[index];
    if(state.placed) return CGPointMake(r.origin.x+state.x*r.size.width,r.origin.y+state.y*r.size.height);
    const HaloControlSpec *spec=&halo_control_specs[index];
    /* Short screens pull the bottom clusters down a little so they clear
       the controls along the top. */
    CGFloat s=[self layoutScale],sy=s*MIN(1.0,r.size.height/372.0);
    switch(spec->anchor) {
    case HaloAnchorBottomLeft: return CGPointMake(CGRectGetMinX(r)+spec->dx*s,CGRectGetMaxY(r)-spec->dy*sy);
    case HaloAnchorBottomRight: return CGPointMake(CGRectGetMaxX(r)-spec->dx*s,CGRectGetMaxY(r)-spec->dy*sy);
    case HaloAnchorTopLeft: return CGPointMake(CGRectGetMinX(r)+spec->dx*s,CGRectGetMinY(r)+spec->dy*s);
    case HaloAnchorTopCenter: return CGPointMake(CGRectGetMidX(r)+spec->dx*s,CGRectGetMinY(r)+spec->dy*s);
    }
    return CGPointMake(CGRectGetMidX(r),CGRectGetMidY(r));
}
- (CGPoint)clampCenter:(CGPoint)center diameter:(CGFloat)diameter {
    CGRect r=[self layoutRect];
    CGFloat half=diameter/2;
    center.x=MIN(MAX(center.x,CGRectGetMinX(r)+half),MAX(CGRectGetMinX(r)+half,CGRectGetMaxX(r)-half));
    center.y=MIN(MAX(center.y,CGRectGetMinY(r)+half),MAX(CGRectGetMinY(r)+half,CGRectGetMaxY(r)-half));
    return center;
}
- (CGPoint)homeCenterForControl:(int)index {
    return [self clampCenter:[self centerForControl:index] diameter:[self diameterForControl:index]];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    for(int i=0;i<HaloControlCount;i++) {
        UIView *view=self.controlViews[i];
        CGFloat diameter=[self diameterForControl:i];
        view.bounds=CGRectMake(0,0,diameter,diameter);
        /* A floating stick stays under the thumb until it is released. */
        if(i==HaloControlMove && self.moveTouch) continue;
        view.center=[self homeCenterForControl:i];
        [view setNeedsDisplay];
    }
    CGRect r=[self layoutRect];
    self.editButton.bounds=self.hideButton.bounds=CGRectMake(0,0,36,36);
    self.editButton.center=CGPointMake(CGRectGetMaxX(r)-18,CGRectGetMinY(r)+18);
    self.hideButton.center=CGPointMake(CGRectGetMaxX(r)-62,CGRectGetMinY(r)+18);
    [self bringSubviewToFront:self.hideButton];
    [self bringSubviewToFront:self.editButton];
    if(self.editor) [self bringSubviewToFront:(UIView *)self.editor];
}
- (void)applySettings {
    for(UIView *view in self.controlViews)
        if([view isKindOfClass:HaloButton.class]) [(HaloButton *)view applySettings];
    [self updateVisibility];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    for(UIView *view in self.controlViews)
        if([view isKindOfClass:HaloButton.class]) [(HaloButton *)view applySettings];
}
- (void)updateVisibility {
    HaloTouchSettings *settings=HaloTouchSettings.shared;
    BOOL editing=self.editor!=nil;
    for(int i=0;i<HaloControlCount;i++) {
        UIView *view=self.controlViews[i];
        BOOL hidden=settings.controls[i].hidden;
        view.hidden=!editing && (self.controlsHidden || hidden);
        CGFloat alpha=settings.opacity;
        if(editing && hidden) alpha=.3;
        else if(i==HaloControlMove && settings.floatingStick && !self.moveTouch && !editing) alpha*=.6;
        view.alpha=alpha;
    }
    self.hideButton.hidden=self.editButton.hidden=editing;
    UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    [self.hideButton setImage:[UIImage systemImageNamed:self.controlsHidden?@"eye":@"eye.slash" withConfiguration:configuration] forState:UIControlStateNormal];
    self.hideButton.accessibilityLabel=self.controlsHidden?@"Show controls":@"Hide controls";
}
- (void)reset {
    host_ios_touch_reset();
    self.moveTouch=self.lookTouch=self.lookStickTouch=nil;
    self.moveStick.knob=self.lookStick.knob=CGPointZero;
    self.moveStick.active=self.lookStick.active=NO;
    for(UIView *view in self.controlViews)
        if([view isKindOfClass:HaloButton.class]) [(HaloButton *)view releaseInput];
    host_ios_haptics_stop();
    [self updateVisibility];
    [self setNeedsLayout];
}
- (void)toggleControls {
    [self reset];
    self.controlsHidden=!self.controlsHidden;
    [self updateVisibility];
}
- (void)beginEditing {
    if(self.editor) return;
    [self reset];
    HaloControlEditor *editor=[[HaloControlEditor alloc] initWithControls:self];
    editor.frame=self.bounds;
    editor.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self addSubview:editor];
    self.editor=editor;
    [self updateVisibility];
    [self setNeedsLayout];
}
- (void)finishEditing {
    [HaloTouchSettings.shared save];
    [(UIView *)self.editor removeFromSuperview];
    self.editor=nil;
    host_ios_apply_exit_gesture();
    [self applySettings];
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    /* Every touch belongs to the controls while they are showing: the left
       of the screen moves and the rest aims. Hidden controls let touches
       through except on the two buttons that bring them back. */
    if(self.editor || !self.controlsHidden) return YES;
    for(UIView *view in @[self.hideButton,self.editButton])
        if(!view.hidden && CGRectContainsPoint(CGRectInset(view.frame,-6,-6),point)) return YES;
    return NO;
}

/* ---------- sticks and swiping */

- (BOOL)point:(CGPoint)point inStick:(HaloStickView *)stick {
    CGFloat radius=stick.bounds.size.width/2+10;
    return hypot(point.x-stick.center.x,point.y-stick.center.y)<=radius;
}
/* A finger's offset from a stick's centre as -1…1 deflection with the touch
   dead zone applied, and the knob's position. */
- (CGPoint)deflection:(CGPoint)point base:(CGPoint)base stick:(HaloStickView *)stick knob:(CGPoint *)knob {
    CGFloat travel=stick.travel;
    CGFloat x=(point.x-base.x)/travel,y=(point.y-base.y)/travel,length=hypot(x,y);
    if(length>1) {x/=length;y/=length;length=1;}
    *knob=CGPointMake(x,y);
    if(length<touch_dead_zone) return CGPointZero;
    CGFloat magnitude=(length-touch_dead_zone)/(1-touch_dead_zone);
    return CGPointMake(x/length*magnitude,y/length*magnitude);
}
- (void)beginMove:(UITouch *)touch at:(CGPoint)point {
    self.moveTouch=touch;
    CGPoint base=self.moveStick.center;
    if(HaloTouchSettings.shared.floatingStick) {
        /* Exactly under the thumb, even near an edge: a base pushed inward
           would read the first touch as a push toward that edge. */
        base=point;
        self.moveStick.center=base;
    }
    self.moveBase=base;
    self.moveStick.active=YES;
    self.moveStick.alpha=HaloTouchSettings.shared.opacity;
    [self updateMove:point];
}
- (void)updateMove:(CGPoint)point {
    CGPoint base=self.moveBase;
    CGFloat travel=self.moveStick.travel;
    CGFloat distance=hypot(point.x-base.x,point.y-base.y);
    if(HaloTouchSettings.shared.floatingStick && distance>travel) {
        /* The stick follows a thumb that slides past its edge. */
        CGFloat pull=(distance-travel)/distance;
        base.x+=(point.x-base.x)*pull;
        base.y+=(point.y-base.y)*pull;
        self.moveBase=base;
        self.moveStick.center=base;
    }
    CGPoint knob;
    CGPoint value=[self deflection:point base:base stick:self.moveStick knob:&knob];
    self.moveStick.knob=knob;
    axis_state(SDL_GAMEPAD_AXIS_LEFTX,stick_value(value.x));
    axis_state(SDL_GAMEPAD_AXIS_LEFTY,stick_value(value.y));
}
- (void)endMove {
    self.moveTouch=nil;
    axis_state(SDL_GAMEPAD_AXIS_LEFTX,0);
    axis_state(SDL_GAMEPAD_AXIS_LEFTY,0);
    self.moveStick.knob=CGPointZero;
    self.moveStick.active=NO;
    CGPoint home=[self homeCenterForControl:HaloControlMove];
    [UIView animateWithDuration:.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction
        animations:^{self.moveStick.center=home;[self updateVisibility];} completion:nil];
}
- (void)updateLookStick:(CGPoint)point {
    CGPoint knob;
    CGPoint value=[self deflection:point base:self.lookStick.center stick:self.lookStick knob:&knob];
    self.lookStick.knob=knob;
    axis_state(SDL_GAMEPAD_AXIS_RIGHTX,stick_value(value.x));
    axis_state(SDL_GAMEPAD_AXIS_RIGHTY,stick_value(value.y));
}
- (void)endLookStick {
    self.lookStickTouch=nil;
    self.lookStick.knob=CGPointZero;
    self.lookStick.active=NO;
    axis_state(SDL_GAMEPAD_AXIS_RIGHTX,0);
    axis_state(SDL_GAMEPAD_AXIS_RIGHTY,0);
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if(self.controlsHidden || self.editor) return;
    HaloTouchSettings *settings=HaloTouchSettings.shared;
    CGRect r=[self layoutRect];
    BOOL moveShown=!settings.controls[HaloControlMove].hidden;
    BOOL lookStickShown=!settings.controls[HaloControlLook].hidden;
    for(UITouch *touch in touches) {
        CGPoint point=[touch locationInView:self];
        if(lookStickShown && !self.lookStickTouch && [self point:point inStick:self.lookStick]) {
            self.lookStickTouch=touch;
            self.lookStick.active=YES;
            [self updateLookStick:point];
            continue;
        }
        BOOL inMoveZone=moveShown && (point.x<CGRectGetMinX(r)+r.size.width*move_zone_fraction || [self point:point inStick:self.moveStick]);
        if(inMoveZone) {
            if(!self.moveTouch) [self beginMove:touch at:point];
            continue;
        }
        if(!self.lookTouch) {
            self.lookTouch=touch;
            self.lookLast=point;
        }
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    for(UITouch *touch in touches) {
        CGPoint point=[touch locationInView:self];
        if(touch==self.moveTouch) [self updateMove:point];
        else if(touch==self.lookStickTouch) [self updateLookStick:point];
        else if(touch==self.lookTouch) {
            push_look(point.x-self.lookLast.x,point.y-self.lookLast.y);
            self.lookLast=point;
        }
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    for(UITouch *touch in touches) {
        if(touch==self.moveTouch) [self endMove];
        if(touch==self.lookStickTouch) [self endLookStick];
        if(touch==self.lookTouch) self.lookTouch=nil;
    }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}
@end

void host_ios_touch_attach(SDL_Window *window) {
    UIWindow *native=(__bridge UIWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(window),SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER,NULL);
    /* Retire SDL's temporary launch window before entering the non-returning
       game loop. Its fade animation can otherwise keep accessibility/input
       attached to the launch controller on recent scene-based iOS versions. */
    for(UIWindow *candidate in native.windowScene.windows) {
        if(candidate!=native && [NSStringFromClass(candidate.rootViewController.class) hasPrefix:@"SDLLaunch"])
            candidate.hidden=YES;
    }
    [native makeKeyAndVisible];
    host_ios_require_landscape(native);
    UIView *root=native.rootViewController.view;
    HaloControls *controls=[[HaloControls alloc]initWithFrame:root.bounds];
    [root addSubview:controls];
    host_logf(HOST_LOG_INFO,"touch controls attached, %.0fx%.0f",root.bounds.size.width,root.bounds.size.height);
}
