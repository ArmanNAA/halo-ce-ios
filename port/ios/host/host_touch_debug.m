/* The debug menu, opened from the control editor: the developer cheats this
   build still has, game speed, difficulty, and loading any level on the
   device. Each choice is a console command handed to the game
   (host_ios_run_command); the game runs it on its next frame as if it had
   been typed into the console (console_update, source/main/console.c). */
#import <UIKit/UIKit.h>
#include <SDL3/SDL.h>
#include <stdio.h>
#include <sys/mman.h>
#include "ios_host.h"
#import "host_touch.h"

/* The event the game's platform layer queues commands from
   (port/linux/src/sdl_platform.c); its code is the guest address of the
   command's text. */
#define HALO_IOS_EVENT_COMMAND (SDL_EVENT_USER + 0x48)

void host_ios_run_command(const char *command) {
    /* The game copies the text when it reads the event, a frame or so
       later; a ring of slots in guest memory outlives that by far. */
    enum {slot_count=32, slot_length=256};
    static char *ring;
    static unsigned next;
    if(!command || !*command) return;
    if(!ring) {
        ring=host_low_map(slot_count*slot_length,PROT_READ|PROT_WRITE);
        if(!ring) {host_logf(HOST_LOG_WARN,"debug menu: no guest memory for commands");return;}
    }
    char *slot=ring+(next++%slot_count)*slot_length;
    snprintf(slot,slot_length,"%s",command);
    SDL_Event event;
    SDL_zero(event);
    event.type=HALO_IOS_EVENT_COMMAND;
    event.user.timestamp=SDL_GetTicksNS();
    event.user.code=(Sint32)guest_pointer(slot);
    if(SDL_PushEvent(&event)) host_logf(HOST_LOG_INFO,"debug menu: %s",command);
    else host_logf(HOST_LOG_WARN,"debug menu: could not queue %s: %s",command,SDL_GetError());
}

/* ---------- what the menu offers */

static const struct {
    const char *command;   /* a global, or a function taking true or false */
    const char *title;
    const char *detail;
    BOOL on;               /* the game's default */
} toggles[]={
    {"cheat_deathless_player","God mode","You can't die.",NO},
    {"cheat_infinite_ammo","Infinite ammo","Reloads and grenades never run out.",NO},
    {"cheat_bottomless_clip","Bottomless clip","Fire without reloading.",NO},
    {"cheat_super_jump","Super jump",NULL,NO},
    {"cheat_omnipotent","One-hit kills",NULL,NO},
    {"cheat_medusa","Medusa","Enemies that see you die.",NO},
    {"cheat_jetpack","Jetpack",NULL,NO},
    {"cheat_bump_possession","Bump possession","Take over a character by walking into it.",NO},
    {"cheat_reflexive_damage_effects","Reflexive damage effects",NULL,NO},
    {"cheat_controller","Controller cheats","Hold Back and press a button to run that line of cheats.txt.",NO},
    {"show_hud","Show HUD",NULL,YES},
};
enum {toggle_count=sizeof(toggles)/sizeof(toggles[0])};

static const struct {
    const char *command;
    const char *title;
} actions[]={
    {"cheat_all_weapons","All weapons"},
    {"cheat_all_vehicles","All vehicles"},
    {"cheat_all_powerups","All power-ups"},
    {"cheat_active_camouflage","Camouflage"},
    {"cheat_teleport_to_camera","Teleport to camera"},
    {"game_revert","Last checkpoint"},
    {"game_won","Finish level"},
};

static const float speeds[]={.25f,.5f,1,2};
static const char *difficulties[]={"easy","normal","hard","impossible"};

static const struct {
    const char *map;
    const char *title;
} campaign[]={
    {"a10","The Pillar of Autumn"},{"a30","Halo"},{"a50","The Truth and Reconciliation"},
    {"b30","The Silent Cartographer"},{"b40","Assault on the Control Room"},{"c10","343 Guilty Spark"},
    {"c20","The Library"},{"c40","Two Betrayals"},{"d20","Keyes"},{"d40","The Maw"},
};
static const struct {
    const char *map;
    const char *title;
} multiplayer[]={
    {"beavercreek","Battle Creek"},{"bloodgulch","Blood Gulch"},{"boardingaction","Boarding Action"},
    {"carousel","Derelict"},{"chillout","Chill Out"},{"damnation","Damnation"},{"hangemhigh","Hang 'Em High"},
    {"longest","Longest"},{"prisoner","Prisoner"},{"putput","Chiron TL-34"},{"ratrace","Rat Race"},
    {"sidewinder","Sidewinder"},{"wizard","Wizard"},
};

/* What the menu has set this session; the game keeps these until it quits. */
static BOOL toggle_state[toggle_count];
static BOOL toggle_state_ready;
static NSInteger speed_index=2, difficulty_index=1;

/* ---------- the menu */

@interface HaloDebugMenu ()
@property(nonatomic, strong) UIVisualEffectView *background;
@end

@implementation HaloDebugMenu

- (UILabel *)label:(NSString *)text style:(UIFontTextStyle)style alpha:(CGFloat)alpha {
    UILabel *label=[UILabel new];
    label.text=text;
    label.font=[UIFont preferredFontForTextStyle:style];
    label.textColor=[UIColor colorWithWhite:1 alpha:alpha];
    label.numberOfLines=0;
    return label;
}
- (UILabel *)heading:(NSString *)text {
    UILabel *label=[self label:text style:UIFontTextStyleSubheadline alpha:1];
    label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textColor=halo_hud_color(1);
    return label;
}
- (UIView *)row:(UIView *)left control:(UIView *)control {
    [left setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [left setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[left,control]];
    row.axis=UILayoutConstraintAxisHorizontal;
    row.alignment=UIStackViewAlignmentCenter;
    row.spacing=12;
    return row;
}
- (UIButton *)listButton:(NSString *)title detail:(NSString *)detail tag:(NSInteger)tag action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    NSString *text=detail.length?[NSString stringWithFormat:@"%@   %@",title,detail]:title;
    [button setTitle:text forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    button.titleLabel.adjustsFontSizeToFitWidth=YES;
    button.titleLabel.minimumScaleFactor=.7;
    button.tintColor=UIColor.whiteColor;
    button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    button.backgroundColor=[halo_hud_color(1) colorWithAlphaComponent:.12];
    button.layer.cornerRadius=8;
    button.layer.borderWidth=1;
    button.layer.borderColor=[halo_hud_color(1) colorWithAlphaComponent:.35].CGColor;
    button.tag=tag;
    [button.heightAnchor constraintEqualToConstant:38].active=YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (UISegmentedControl *)segments:(NSArray<NSString *> *)items selected:(NSInteger)selected action:(SEL)action {
    UISegmentedControl *control=[[UISegmentedControl alloc] initWithItems:items];
    control.selectedSegmentIndex=selected;
    control.selectedSegmentTintColor=halo_hud_color(1);
    [control addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return control;
}

/* the level files the import put in Documents/maps */
- (NSSet<NSString *> *)installedMaps {
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSArray<NSString *> *files=[NSFileManager.defaultManager contentsOfDirectoryAtPath:[documents stringByAppendingPathComponent:@"maps"] error:NULL];
    NSMutableSet<NSString *> *maps=[NSMutableSet set];
    for(NSString *file in files)
        if([file.pathExtension.lowercaseString isEqualToString:@"map"]) [maps addObject:file.stringByDeletingPathExtension.lowercaseString];
    return maps;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame])) return nil;
    if(!toggle_state_ready) {
        for(int i=0;i<toggle_count;i++) toggle_state[i]=toggles[i].on;
        toggle_state_ready=YES;
    }
    self.layer.cornerRadius=16;
    self.clipsToBounds=YES;
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.background=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    self.background.frame=self.bounds;
    self.background.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.background];
    UIView *content=self.background.contentView;

    UILabel *title=[self label:@"Debug Menu" style:UIFontTextStyleHeadline alpha:1];
    title.translatesAutoresizingMaskIntoConstraints=NO;
    [content addSubview:title];
    UIButton *back=[UIButton buttonWithType:UIButtonTypeSystem];
    back.translatesAutoresizingMaskIntoConstraints=NO;
    [back setTitle:@"Back" forState:UIControlStateNormal];
    back.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    back.tintColor=halo_hud_color(1);
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:back];
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.alwaysBounceVertical=YES;
    scroll.indicatorStyle=UIScrollViewIndicatorStyleWhite;
    [content addSubview:scroll];
    UIStackView *stack=[UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    stack.axis=UILayoutConstraintAxisVertical;
    stack.spacing=10;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [back.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [back.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:back.leadingAnchor constant:-8],
        [scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:4],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];

    UILabel *warning=[self label:@"Developer commands from the original build. Some can crash the game; your saves are not touched."
        style:UIFontTextStyleCaption1 alpha:.6];
    [stack addArrangedSubview:warning];

    [stack addArrangedSubview:[self heading:@"Cheats"]];
    for(int i=0;i<toggle_count;i++) {
        UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[[self label:@(toggles[i].title) style:UIFontTextStyleSubheadline alpha:1]]];
        text.axis=UILayoutConstraintAxisVertical;
        text.spacing=2;
        if(toggles[i].detail) [text addArrangedSubview:[self label:@(toggles[i].detail) style:UIFontTextStyleCaption1 alpha:.6]];
        UISwitch *toggle=[UISwitch new];
        toggle.on=toggle_state[i];
        toggle.onTintColor=halo_hud_color(1);
        toggle.tag=i;
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        [stack addArrangedSubview:[self row:text control:toggle]];
    }

    [stack addArrangedSubview:[self heading:@"Instant"]];
    for(NSInteger i=0;i<(NSInteger)(sizeof(actions)/sizeof(actions[0]));i++)
        [stack addArrangedSubview:[self listButton:@(actions[i].title) detail:nil tag:i action:@selector(actionTapped:)]];

    [stack addArrangedSubview:[self heading:@"Game speed"]];
    [stack addArrangedSubview:[self segments:@[@"¼×",@"½×",@"1×",@"2×"] selected:speed_index action:@selector(speedChanged:)]];

    [stack addArrangedSubview:[self heading:@"Difficulty"]];
    [stack addArrangedSubview:[self segments:@[@"Easy",@"Normal",@"Heroic",@"Legendary"] selected:difficulty_index action:@selector(difficultyChanged:)]];
    [stack addArrangedSubview:[self label:@"Used by the next level that loads." style:UIFontTextStyleCaption1 alpha:.6]];

    NSSet<NSString *> *installed=self.installedMaps;
    [stack addArrangedSubview:[self heading:@"Load a level"]];
    NSUInteger shown=0;
    for(NSInteger i=0;i<(NSInteger)(sizeof(campaign)/sizeof(campaign[0]));i++) {
        if(installed.count && ![installed containsObject:@(campaign[i].map)]) continue;
        [stack addArrangedSubview:[self listButton:@(campaign[i].title) detail:@(campaign[i].map) tag:i action:@selector(campaignTapped:)]];
        shown++;
    }
    if(!shown) [stack addArrangedSubview:[self label:@"No campaign levels found in the maps folder." style:UIFontTextStyleCaption1 alpha:.6]];
    NSMutableArray<UIButton *> *multiplayerButtons=[NSMutableArray array];
    for(NSInteger i=0;i<(NSInteger)(sizeof(multiplayer)/sizeof(multiplayer[0]));i++) {
        if(![installed containsObject:@(multiplayer[i].map)]) continue;
        [multiplayerButtons addObject:[self listButton:@(multiplayer[i].title) detail:@(multiplayer[i].map) tag:i action:@selector(multiplayerTapped:)]];
    }
    if(multiplayerButtons.count) {
        [stack addArrangedSubview:[self heading:@"Explore a multiplayer map"]];
        [stack addArrangedSubview:[self label:@"Loads it as a solo level. Experimental: some may not start." style:UIFontTextStyleCaption1 alpha:.6]];
        for(UIButton *button in multiplayerButtons) [stack addArrangedSubview:button];
    }
    return self;
}

- (void)close {
    if(self.onClose) self.onClose();
}
- (void)toggleChanged:(UISwitch *)toggle {
    NSInteger i=toggle.tag;
    if(i<0 || i>=toggle_count) return;
    toggle_state[i]=toggle.on;
    host_ios_run_command([NSString stringWithFormat:@"%s %s",toggles[i].command,toggle.on?"true":"false"].UTF8String);
    host_ios_haptics_tap();
}
- (void)actionTapped:(UIButton *)button {
    NSInteger i=button.tag;
    if(i<0 || i>=(NSInteger)(sizeof(actions)/sizeof(actions[0]))) return;
    host_ios_run_command(actions[i].command);
    host_ios_haptics_tap();
}
- (void)speedChanged:(UISegmentedControl *)control {
    speed_index=control.selectedSegmentIndex;
    if(speed_index<0 || speed_index>=(NSInteger)(sizeof(speeds)/sizeof(speeds[0]))) return;
    host_ios_run_command([NSString stringWithFormat:@"game_speed %.2f",speeds[speed_index]].UTF8String);
}
- (void)difficultyChanged:(UISegmentedControl *)control {
    difficulty_index=control.selectedSegmentIndex;
    if(difficulty_index<0 || difficulty_index>3) return;
    host_ios_run_command([NSString stringWithFormat:@"game_difficulty_set %s",difficulties[difficulty_index]].UTF8String);
}
- (void)loadScenario:(NSString *)scenario {
    host_ios_run_command([NSString stringWithFormat:@"game_difficulty_set %s",difficulties[MAX(0,MIN(3,difficulty_index))]].UTF8String);
    /* the scenario's tag path; the game loads maps/<last part>.map */
    host_ios_run_command([NSString stringWithFormat:@"map_name \"%@\"",scenario].UTF8String);
    host_ios_haptics_tap();
    if(self.onPlay) self.onPlay();
}
- (void)campaignTapped:(UIButton *)button {
    NSInteger i=button.tag;
    if(i<0 || i>=(NSInteger)(sizeof(campaign)/sizeof(campaign[0]))) return;
    NSString *map=@(campaign[i].map);
    [self loadScenario:[NSString stringWithFormat:@"levels\\%@\\%@",map,map]];
}
- (void)multiplayerTapped:(UIButton *)button {
    NSInteger i=button.tag;
    if(i<0 || i>=(NSInteger)(sizeof(multiplayer)/sizeof(multiplayer[0]))) return;
    NSString *map=@(multiplayer[i].map);
    [self loadScenario:[NSString stringWithFormat:@"levels\\test\\%@\\%@",map,map]];
}
@end
