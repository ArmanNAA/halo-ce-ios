/* The in-game control editor: drag any control to move it; tap one to change
   its size, icon or visibility; tune aiming and feel in the panel. Changes
   show immediately and are saved to Documents/controls.json. */
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "ios_host.h"
#import "host_orientation.h"
#import "host_touch.h"

enum {
    icon_tile_text=1,
    icon_tile_custom=2,
    icon_tile_symbol=100, /* + the SF Symbol's index */
    icon_tile_halo=300,   /* + the Halo-style icon's index */
};

static UIColor *accent_color(void) {
    return [UIColor colorWithRed:.35 green:.8 blue:1 alpha:1];
}

@interface HaloControlEditor () <UIDocumentPickerDelegate>
@property(nonatomic, weak) HaloControls *controls;
@property(nonatomic, strong) UIView *dimView;
@property(nonatomic) int selected;
@property(nonatomic) int pickingFor;
@property(nonatomic, strong) UITouch *dragTouch;
@property(nonatomic) CGPoint dragOffset;
@property(nonatomic, strong) UIView *selectionRing;
@property(nonatomic, strong) UIVisualEffectView *panel;
@property(nonatomic) BOOL panelPlaced;
@property(nonatomic) CGPoint panelCenter;
@property(nonatomic, strong) UILabel *selectedTitle;
@property(nonatomic, strong) UILabel *hint;
@property(nonatomic, strong) UIStackView *selectedSection;
@property(nonatomic, strong) UISlider *sizeSlider;
@property(nonatomic, strong) UISwitch *visibleSwitch;
@property(nonatomic, strong) UISwitch *aimSwitch;
@property(nonatomic, strong) UIView *aimRow;
@property(nonatomic, strong) UIView *iconSection;
@property(nonatomic, strong) UIStackView *iconRow;
@property(nonatomic, strong) UILabel *sensitivityValue;
@property(nonatomic, strong) UILabel *opacityValue;
@property(nonatomic, strong) UIButton *resetButton;
@property(nonatomic, strong) UISegmentedControl *styleControl;
@property(nonatomic, strong) HaloDebugMenu *debugMenu;
@property(nonatomic) BOOL resetArmed;
@end

@implementation HaloControlEditor

- (instancetype)initWithControls:(HaloControls *)controls {
    if(!(self=[super initWithFrame:controls.bounds])) return nil;
    self.controls=controls;
    self.selected=-1;
    self.pickingFor=-1;
    self.backgroundColor=UIColor.clearColor;
    /* Dim the game behind the controls, not the controls themselves. */
    self.dimView=[[UIView alloc] initWithFrame:controls.bounds];
    self.dimView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.dimView.backgroundColor=[UIColor colorWithWhite:0 alpha:.45];
    self.dimView.userInteractionEnabled=NO;
    [controls insertSubview:self.dimView atIndex:0];
    self.selectionRing=[UIView new];
    self.selectionRing.userInteractionEnabled=NO;
    self.selectionRing.layer.borderColor=accent_color().CGColor;
    self.selectionRing.layer.borderWidth=2.5;
    self.selectionRing.hidden=YES;
    [self addSubview:self.selectionRing];
    [self buildPanel];
    [self selectControl:-1];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveSettings)
        name:UIApplicationWillResignActiveNotification object:nil];
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)removeFromSuperview {
    [self.dimView removeFromSuperview];
    [super removeFromSuperview];
}
- (void)saveSettings {
    [HaloTouchSettings.shared save];
}

/* ---------- building the panel */

- (UILabel *)labelWithText:(NSString *)text style:(UIFontTextStyle)style {
    UILabel *label=[UILabel new];
    label.text=text;
    label.font=[UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory=NO;
    label.textColor=UIColor.whiteColor;
    label.numberOfLines=0;
    return label;
}
- (UIStackView *)rowWithTitle:(NSString *)title control:(UIView *)control {
    UILabel *label=[self labelWithText:title style:UIFontTextStyleSubheadline];
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[label,control]];
    row.axis=UILayoutConstraintAxisHorizontal;
    row.alignment=UIStackViewAlignmentCenter;
    row.spacing=12;
    return row;
}
- (UIStackView *)sliderRowWithTitle:(NSString *)title slider:(UISlider *)slider value:(UILabel *)value {
    UILabel *label=[self labelWithText:title style:UIFontTextStyleSubheadline];
    [label.widthAnchor constraintEqualToConstant:104].active=YES;
    NSMutableArray<UIView *> *views=[NSMutableArray arrayWithObjects:label,slider,nil];
    if(value) {
        value.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
        value.textColor=[UIColor colorWithWhite:1 alpha:.75];
        value.textAlignment=NSTextAlignmentRight;
        [value.widthAnchor constraintEqualToConstant:44].active=YES;
        [views addObject:value];
    }
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:views];
    row.axis=UILayoutConstraintAxisHorizontal;
    row.alignment=UIStackViewAlignmentCenter;
    row.spacing=10;
    return row;
}
- (UISlider *)sliderFrom:(float)minimum to:(float)maximum value:(float)value action:(SEL)action {
    UISlider *slider=[UISlider new];
    slider.minimumValue=minimum;
    slider.maximumValue=maximum;
    slider.value=value;
    slider.minimumTrackTintColor=accent_color();
    [slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(saveSettings) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    return slider;
}
- (UISwitch *)switchOn:(BOOL)on action:(SEL)action {
    UISwitch *toggle=[UISwitch new];
    toggle.on=on;
    toggle.onTintColor=accent_color();
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return toggle;
}
- (UIView *)separator {
    UIView *line=[UIView new];
    line.backgroundColor=[UIColor colorWithWhite:1 alpha:.15];
    [line.heightAnchor constraintEqualToConstant:1].active=YES;
    return line;
}

- (void)buildPanel {
    HaloTouchSettings *settings=HaloTouchSettings.shared;
    UIVisualEffectView *panel=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    panel.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    panel.layer.cornerRadius=16;
    panel.clipsToBounds=YES;
    [self addSubview:panel];
    self.panel=panel;
    UIView *content=panel.contentView;

    /* The header: drag it to move the panel out of the way. */
    UIView *header=[UIView new];
    header.translatesAutoresizingMaskIntoConstraints=NO;
    [content addSubview:header];
    UIView *grabber=[UIView new];
    grabber.translatesAutoresizingMaskIntoConstraints=NO;
    grabber.backgroundColor=[UIColor colorWithWhite:1 alpha:.35];
    grabber.layer.cornerRadius=2.5;
    [header addSubview:grabber];
    UILabel *title=[self labelWithText:@"Customize Controls" style:UIFontTextStyleHeadline];
    title.translatesAutoresizingMaskIntoConstraints=NO;
    [header addSubview:title];
    UIButton *done=[UIButton buttonWithType:UIButtonTypeSystem];
    done.translatesAutoresizingMaskIntoConstraints=NO;
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    done.tintColor=accent_color();
    [done addTarget:self action:@selector(done) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:done];
    [header addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(movePanel:)]];

    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.alwaysBounceVertical=YES;
    scroll.indicatorStyle=UIScrollViewIndicatorStyleWhite;
    [content addSubview:scroll];
    UIStackView *stack=[UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    stack.axis=UILayoutConstraintAxisVertical;
    stack.spacing=12;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:content.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:52],
        [grabber.topAnchor constraintEqualToAnchor:header.topAnchor constant:6],
        [grabber.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [grabber.widthAnchor constraintEqualToConstant:36],
        [grabber.heightAnchor constraintEqualToConstant:5],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor constant:3],
        [done.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [done.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:done.leadingAnchor constant:-8],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:4],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32],
    ]];

    /* The selected control */
    self.selectedTitle=[self labelWithText:@"" style:UIFontTextStyleSubheadline];
    self.selectedTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.selectedTitle.textColor=accent_color();
    [stack addArrangedSubview:self.selectedTitle];
    self.hint=[self labelWithText:@"Drag any control to move it. Tap one to resize it, hide it or give it a new icon."
        style:UIFontTextStyleFootnote];
    self.hint.textColor=[UIColor colorWithWhite:1 alpha:.7];
    [stack addArrangedSubview:self.hint];

    self.sizeSlider=[self sliderFrom:.5 to:2 value:1 action:@selector(sizeChanged:)];
    self.visibleSwitch=[self switchOn:YES action:@selector(visibleChanged:)];
    self.aimSwitch=[self switchOn:NO action:@selector(aimChanged:)];
    self.aimRow=[self rowWithTitle:@"Drag to aim while held" control:self.aimSwitch];
    self.iconRow=[UIStackView new];
    self.iconRow.axis=UILayoutConstraintAxisHorizontal;
    self.iconRow.spacing=8;
    self.iconRow.translatesAutoresizingMaskIntoConstraints=NO;
    UIScrollView *iconScroll=[UIScrollView new];
    iconScroll.showsHorizontalScrollIndicator=NO;
    iconScroll.translatesAutoresizingMaskIntoConstraints=NO;
    [iconScroll addSubview:self.iconRow];
    [NSLayoutConstraint activateConstraints:@[
        [iconScroll.heightAnchor constraintEqualToConstant:46],
        [self.iconRow.topAnchor constraintEqualToAnchor:iconScroll.contentLayoutGuide.topAnchor constant:1],
        [self.iconRow.bottomAnchor constraintEqualToAnchor:iconScroll.contentLayoutGuide.bottomAnchor constant:-1],
        [self.iconRow.leadingAnchor constraintEqualToAnchor:iconScroll.contentLayoutGuide.leadingAnchor],
        [self.iconRow.trailingAnchor constraintEqualToAnchor:iconScroll.contentLayoutGuide.trailingAnchor],
        [self.iconRow.heightAnchor constraintEqualToAnchor:iconScroll.frameLayoutGuide.heightAnchor constant:-2],
    ]];
    UILabel *iconTitle=[self labelWithText:@"Icon" style:UIFontTextStyleSubheadline];
    UILabel *iconHint=[self labelWithText:@"The photo tile uses any image from Files." style:UIFontTextStyleCaption1];
    iconHint.textColor=[UIColor colorWithWhite:1 alpha:.6];
    UIStackView *iconSection=[[UIStackView alloc] initWithArrangedSubviews:@[iconTitle,iconScroll,iconHint]];
    iconSection.axis=UILayoutConstraintAxisVertical;
    iconSection.spacing=6;
    self.iconSection=iconSection;
    self.selectedSection=[[UIStackView alloc] initWithArrangedSubviews:@[
        [self sliderRowWithTitle:@"Size" slider:self.sizeSlider value:nil],
        [self rowWithTitle:@"Show on screen" control:self.visibleSwitch],
        self.aimRow,
        iconSection,
    ]];
    self.selectedSection.axis=UILayoutConstraintAxisVertical;
    self.selectedSection.spacing=12;
    [stack addArrangedSubview:self.selectedSection];

    /* Everything else */
    [stack addArrangedSubview:[self separator]];
    self.styleControl=[[UISegmentedControl alloc] initWithItems:@[@"Standard",@"Halo"]];
    self.styleControl.selectedSegmentIndex=settings.haloStyle?1:0;
    self.styleControl.selectedSegmentTintColor=accent_color();
    [self.styleControl addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:[self rowWithTitle:@"Button style" control:self.styleControl]];
    UILabel *styleHint=[self labelWithText:@"Halo gives every button HUD-blue colors and Halo-style icons. Your own images stay."
        style:UIFontTextStyleCaption1];
    styleHint.textColor=[UIColor colorWithWhite:1 alpha:.6];
    [stack addArrangedSubview:styleHint];
    [stack addArrangedSubview:[self separator]];
    UILabel *feel=[self labelWithText:@"Aiming and feel" style:UIFontTextStyleSubheadline];
    feel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [stack addArrangedSubview:feel];
    UILabel *aimHint=[self labelWithText:@"Swipe anywhere on the right side to look around, or drag FIRE while shooting. In menus, tap an item to pick it and drag to scroll."
        style:UIFontTextStyleFootnote];
    aimHint.textColor=[UIColor colorWithWhite:1 alpha:.7];
    [stack addArrangedSubview:aimHint];
    self.sensitivityValue=[UILabel new];
    [stack addArrangedSubview:[self sliderRowWithTitle:@"Look speed"
        slider:[self sliderFrom:.25 to:3 value:(float)settings.lookSensitivity action:@selector(sensitivityChanged:)]
        value:self.sensitivityValue]];
    [stack addArrangedSubview:[self rowWithTitle:@"Invert look" control:[self switchOn:settings.invertLook action:@selector(invertChanged:)]]];
    [stack addArrangedSubview:[self rowWithTitle:@"Move stick follows your thumb"
        control:[self switchOn:settings.floatingStick action:@selector(floatingChanged:)]]];
    self.opacityValue=[UILabel new];
    [stack addArrangedSubview:[self sliderRowWithTitle:@"Opacity"
        slider:[self sliderFrom:.2f to:1 value:(float)settings.opacity action:@selector(opacityChanged:)]
        value:self.opacityValue]];
    [stack addArrangedSubview:[self rowWithTitle:@"Vibration" control:[self switchOn:settings.haptics action:@selector(hapticsChanged:)]]];
    [stack addArrangedSubview:[self rowWithTitle:@"Show button names" control:[self switchOn:settings.showNames action:@selector(namesChanged:)]]];
    [stack addArrangedSubview:[self rowWithTitle:@"Tap crouch to toggle it"
        control:[self switchOn:settings.toggleCrouch action:@selector(crouchChanged:)]]];
    [stack addArrangedSubview:[self rowWithTitle:@"Buttons in menus"
        control:[self switchOn:settings.menuButtons action:@selector(menuButtonsChanged:)]]];
    UILabel *menuHint=[self labelWithText:@"Menus work by touch: tap to pick, drag to scroll, tap with two fingers to go back. This brings back A, B, X, Y and the arrows there too, as does the eye button while a menu is up."
        style:UIFontTextStyleCaption1];
    menuHint.textColor=[UIColor colorWithWhite:1 alpha:.6];
    [stack addArrangedSubview:menuHint];
    [stack addArrangedSubview:[self separator]];
    self.resetButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"Reset Layout" forState:UIControlStateNormal];
    self.resetButton.tintColor=UIColor.systemRedColor;
    self.resetButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    [self.resetButton addTarget:self action:@selector(resetLayout) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.resetButton];
    [stack addArrangedSubview:[self separator]];
    UIButton *debug=[UIButton buttonWithType:UIButtonTypeSystem];
    [debug setTitle:@"Show Debug Menu" forState:UIControlStateNormal];
    debug.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    debug.tintColor=accent_color();
    debug.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeading;
    [debug addTarget:self action:@selector(showDebugMenu) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:debug];
    UILabel *debugHint=[self labelWithText:@"Cheats, game speed, difficulty and loading any level."
        style:UIFontTextStyleCaption1];
    debugHint.textColor=[UIColor colorWithWhite:1 alpha:.6];
    [stack addArrangedSubview:debugHint];
    [self updateValueLabels];
}

/* ---------- placement */

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect area=UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets);
    area=CGRectInset(area,8,8);
    CGFloat width=MIN(380,MAX(300,area.size.width*.46));
    /* Leave the top row (pause, menu arrows) uncovered. */
    CGFloat top=CGRectGetMinY(area)+48;
    CGFloat height=MAX(200,CGRectGetMaxY(area)-top);
    self.panel.bounds=CGRectMake(0,0,width,height);
    CGPoint center=self.panelCenter;
    if(!self.panelPlaced) {
        center=CGPointMake(CGRectGetMidX(area),top+height/2);
        /* Move aside when the panel would cover the selected control. */
        if(self.selected>=0) {
            CGRect control=[self.controls viewForControl:self.selected].frame;
            CGRect panel=CGRectMake(center.x-width/2,center.y-height/2,width,height);
            if(CGRectIntersectsRect(control,panel))
                center.x=CGRectGetMidX(control)>CGRectGetMidX(area)?CGRectGetMinX(area)+width/2:CGRectGetMaxX(area)-width/2;
        }
    }
    center.x=MIN(MAX(center.x,CGRectGetMinX(area)+width/2),MAX(CGRectGetMinX(area)+width/2,CGRectGetMaxX(area)-width/2));
    center.y=MIN(MAX(center.y,CGRectGetMinY(area)+height/2),MAX(CGRectGetMinY(area)+height/2,CGRectGetMaxY(area)-height/2));
    self.panel.center=center;
    if(self.debugMenu) {
        self.debugMenu.bounds=self.panel.bounds;
        self.debugMenu.center=center;
    }
    [self updateRing];
}
- (void)movePanel:(UIPanGestureRecognizer *)pan {
    CGPoint translation=[pan translationInView:self];
    CGPoint center=self.panel.center;
    self.panelCenter=CGPointMake(center.x+translation.x,center.y+translation.y);
    self.panelPlaced=YES;
    [pan setTranslation:CGPointZero inView:self];
    [self setNeedsLayout];
}
- (void)updateRing {
    if(self.selected<0) {self.selectionRing.hidden=YES;return;}
    UIView *view=[self.controls viewForControl:self.selected];
    CGRect frame=[self convertRect:CGRectInset(view.frame,-5,-5) fromView:self.controls];
    self.selectionRing.frame=frame;
    self.selectionRing.layer.cornerRadius=frame.size.width/2;
    self.selectionRing.hidden=NO;
}

/* ---------- choosing and dragging controls */

- (int)controlAtPoint:(CGPoint)point {
    CGPoint local=[self convertPoint:point toView:self.controls];
    int best=-1;
    CGFloat bestDistance=CGFLOAT_MAX;
    for(int i=0;i<HaloControlCount;i++) {
        UIView *view=[self.controls viewForControl:i];
        if(!CGRectContainsPoint(CGRectInset(view.frame,-8,-8),local)) continue;
        /* Overlapping controls go to the one whose centre is nearest. */
        CGFloat distance=hypot(local.x-view.center.x,local.y-view.center.y)/MAX(1,view.bounds.size.width);
        if(distance<bestDistance) {best=i;bestDistance=distance;}
    }
    return best;
}
- (void)selectControl:(int)index {
    self.selected=index;
    HaloTouchSettings *settings=HaloTouchSettings.shared;
    if(index<0) {
        self.selectedTitle.text=@"Tap a control to edit it";
        self.selectedSection.hidden=YES;
        self.hint.hidden=NO;
    } else {
        const HaloControlSpec *spec=&halo_control_specs[index];
        HaloControlState *state=settings.controls[index];
        self.selectedTitle.text=@(spec->name);
        self.selectedSection.hidden=NO;
        self.hint.hidden=YES;
        self.sizeSlider.value=(float)state.scale;
        self.visibleSwitch.on=!state.hidden;
        self.aimSwitch.on=state.aim;
        BOOL stick=spec->kind==HaloControlKindStick;
        self.aimRow.hidden=stick;
        self.iconSection.hidden=stick;
    }
    [self rebuildIcons];
    [self setNeedsLayout];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if(self.dragTouch) return;
    UITouch *touch=touches.anyObject;
    CGPoint point=[touch locationInView:self];
    int index=[self controlAtPoint:point];
    [self selectControl:index];
    if(index<0) return;
    UIView *view=[self.controls viewForControl:index];
    CGPoint center=[self convertPoint:view.center fromView:self.controls];
    self.dragTouch=touch;
    self.dragOffset=CGPointMake(center.x-point.x,center.y-point.y);
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if(!self.dragTouch || ![touches containsObject:self.dragTouch]) return;
    CGPoint point=[self.dragTouch locationInView:self];
    CGPoint center=[self convertPoint:CGPointMake(point.x+self.dragOffset.x,point.y+self.dragOffset.y) toView:self.controls];
    CGRect r=[self.controls layoutRect];
    if(r.size.width<=0 || r.size.height<=0) return;
    CGFloat half=[self.controls viewForControl:self.selected].bounds.size.width/2;
    center.x=MIN(MAX(center.x,CGRectGetMinX(r)+half),MAX(CGRectGetMinX(r)+half,CGRectGetMaxX(r)-half));
    center.y=MIN(MAX(center.y,CGRectGetMinY(r)+half),MAX(CGRectGetMinY(r)+half,CGRectGetMaxY(r)-half));
    HaloControlState *state=HaloTouchSettings.shared.controls[self.selected];
    state.placed=YES;
    state.x=(center.x-CGRectGetMinX(r))/r.size.width;
    state.y=(center.y-CGRectGetMinY(r))/r.size.height;
    [self.controls setNeedsLayout];
    [self.controls layoutIfNeeded];
    [self updateRing];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if(self.dragTouch && [touches containsObject:self.dragTouch]) {
        self.dragTouch=nil;
        [self saveSettings];
        [self setNeedsLayout];
    }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

/* ---------- icons */

- (UIButton *)iconTile:(NSInteger)tag image:(UIImage *)image title:(NSString *)title selected:(BOOL)selected {
    UIButton *tile=[UIButton buttonWithType:UIButtonTypeSystem];
    tile.tag=tag;
    tile.tintColor=UIColor.whiteColor;
    if(image) [tile setImage:image forState:UIControlStateNormal];
    else {
        [tile setTitle:title forState:UIControlStateNormal];
        tile.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        tile.titleLabel.adjustsFontSizeToFitWidth=YES;
        tile.titleLabel.minimumScaleFactor=.5;
    }
    tile.imageView.contentMode=UIViewContentModeScaleAspectFit;
    tile.backgroundColor=selected?[accent_color() colorWithAlphaComponent:.3]:[UIColor colorWithWhite:1 alpha:.08];
    tile.layer.cornerRadius=10;
    tile.layer.borderWidth=selected?2:0;
    tile.layer.borderColor=accent_color().CGColor;
    tile.clipsToBounds=YES;
    [tile.widthAnchor constraintEqualToConstant:44].active=YES;
    [tile.heightAnchor constraintEqualToConstant:44].active=YES;
    [tile addTarget:self action:@selector(iconTapped:) forControlEvents:UIControlEventTouchUpInside];
    return tile;
}
- (void)rebuildIcons {
    for(UIView *view in self.iconRow.arrangedSubviews.copy) {
        [self.iconRow removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if(self.selected<0 || halo_control_specs[self.selected].kind==HaloControlKindStick) return;
    HaloTouchSettings *settings=HaloTouchSettings.shared;
    NSString *current=settings.controls[self.selected].icon;
    /* tiles are drawn as a 50-point button's icon would be */
    const CGFloat tile_diameter=50;
    NSArray<NSString *> *halo=halo_control_halo_icons(self.selected);
    for(NSUInteger i=0;i<halo.count;i++) {
        NSString *icon=[@"halo:" stringByAppendingString:halo[i]];
        UIImage *image=[settings imageForIcon:icon control:self.selected diameter:tile_diameter];
        if(!image) continue;
        [self.iconRow addArrangedSubview:[self iconTile:icon_tile_halo+(NSInteger)i image:image title:nil
            selected:[current isEqualToString:icon]]];
    }
    NSArray<NSString *> *icons=halo_control_icons(self.selected);
    for(NSUInteger i=0;i<icons.count;i++) {
        NSString *icon=[@"sf:" stringByAppendingString:icons[i]];
        UIImage *image=[settings imageForIcon:icon control:self.selected diameter:tile_diameter];
        if(!image) continue;
        [self.iconRow addArrangedSubview:[self iconTile:icon_tile_symbol+(NSInteger)i image:image title:nil
            selected:[current isEqualToString:icon]]];
    }
    [self.iconRow addArrangedSubview:[self iconTile:icon_tile_text image:nil
        title:@(halo_control_specs[self.selected].text) selected:[current isEqualToString:@"text"]]];
    UIImageSymbolConfiguration *configuration=[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    UIImage *custom=[UIImage imageWithContentsOfFile:[settings customIconPath:self.selected]];
    UIImage *photo=custom?[custom imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
        :[UIImage systemImageNamed:@"photo.badge.plus" withConfiguration:configuration];
    if(!photo) photo=[UIImage systemImageNamed:@"photo" withConfiguration:configuration];
    [self.iconRow addArrangedSubview:[self iconTile:icon_tile_custom image:photo title:@"…" selected:[current isEqualToString:@"custom"]]];
}
- (void)setIcon:(NSString *)icon {
    if(self.selected<0) return;
    HaloTouchSettings.shared.controls[self.selected].icon=icon;
    [self.controls applySettings];
    [self rebuildIcons];
    [self saveSettings];
}
- (void)iconTapped:(UIButton *)tile {
    if(self.selected<0) return;
    if(tile.tag>=icon_tile_halo) {
        NSArray<NSString *> *icons=halo_control_halo_icons(self.selected);
        NSInteger index=tile.tag-icon_tile_halo;
        if(index<(NSInteger)icons.count) [self setIcon:[@"halo:" stringByAppendingString:icons[(NSUInteger)index]]];
    } else if(tile.tag>=icon_tile_symbol) {
        NSArray<NSString *> *icons=halo_control_icons(self.selected);
        NSInteger index=tile.tag-icon_tile_symbol;
        if(index<(NSInteger)icons.count) [self setIcon:[@"sf:" stringByAppendingString:icons[(NSUInteger)index]]];
    } else if(tile.tag==icon_tile_text) {
        [self setIcon:@"text"];
    } else if(tile.tag==icon_tile_custom) {
        HaloTouchSettings *settings=HaloTouchSettings.shared;
        BOOL exists=[NSFileManager.defaultManager fileExistsAtPath:[settings customIconPath:self.selected]];
        /* An image already chosen is picked again by tapping it once it is in use. */
        if(exists && ![settings.controls[self.selected].icon isEqualToString:@"custom"]) [self setIcon:@"custom"];
        else [self chooseCustomIcon];
    }
}
- (void)chooseCustomIcon {
    UIViewController *presenter=self.window.rootViewController;
    while(presenter.presentedViewController) presenter=presenter.presentedViewController;
    if(!presenter) return;
    UIDocumentPickerViewController *picker=[[HaloLandscapeDocumentPicker alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate=self;
    picker.allowsMultipleSelection=NO;
    self.pickingFor=self.selected;
    [presenter presentViewController:picker animated:YES completion:nil];
}
- (UIImage *)iconFromImage:(UIImage *)image {
    CGSize target=CGSizeMake(192,192);
    if(image.size.width<=0 || image.size.height<=0) return nil;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.scale=1;
    format.opaque=NO;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    CGFloat ratio=MIN(target.width/image.size.width,target.height/image.size.height);
    CGSize size=CGSizeMake(image.size.width*ratio,image.size.height*ratio);
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        [image drawInRect:CGRectMake((target.width-size.width)/2,(target.height-size.height)/2,size.width,size.height)];
    }];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    int index=self.pickingFor;
    self.pickingFor=-1;
    NSURL *url=urls.firstObject;
    if(!url || index<0) return;
    BOOL scoped=[url startAccessingSecurityScopedResource];
    UIImage *image=[UIImage imageWithContentsOfFile:url.path];
    if(scoped) [url stopAccessingSecurityScopedResource];
    UIImage *icon=image?[self iconFromImage:image]:nil;
    NSData *png=icon?UIImagePNGRepresentation(icon):nil;
    if(!png) {
        host_logf(HOST_LOG_WARN,"could not read the chosen icon image");
        return;
    }
    NSString *path=[HaloTouchSettings.shared customIconPath:index];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:NULL];
    if(![png writeToFile:path atomically:YES]) {
        host_logf(HOST_LOG_WARN,"could not save the icon to %s",path.fileSystemRepresentation);
        return;
    }
    [self selectControl:index];
    [self setIcon:@"custom"];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    self.pickingFor=-1;
}

/* ---------- settings */

- (void)updateValueLabels {
    HaloTouchSettings *settings=HaloTouchSettings.shared;
    self.sensitivityValue.text=[NSString stringWithFormat:@"%.2f",settings.lookSensitivity];
    self.opacityValue.text=[NSString stringWithFormat:@"%.0f%%",settings.opacity*100];
}
- (void)sizeChanged:(UISlider *)slider {
    if(self.selected<0) return;
    HaloTouchSettings.shared.controls[self.selected].scale=round(slider.value*20)/20;
    [self.controls applySettings];
    [self updateRing];
}
- (void)visibleChanged:(UISwitch *)toggle {
    if(self.selected<0) return;
    HaloTouchSettings.shared.controls[self.selected].hidden=!toggle.on;
    [self.controls applySettings];
    [self saveSettings];
}
- (void)aimChanged:(UISwitch *)toggle {
    if(self.selected<0) return;
    HaloTouchSettings.shared.controls[self.selected].aim=toggle.on;
    [self saveSettings];
}
- (void)sensitivityChanged:(UISlider *)slider {
    HaloTouchSettings.shared.lookSensitivity=round(slider.value*20)/20;
    [self updateValueLabels];
}
- (void)opacityChanged:(UISlider *)slider {
    HaloTouchSettings.shared.opacity=round(slider.value*20)/20;
    [self updateValueLabels];
    [self.controls applySettings];
}
- (void)invertChanged:(UISwitch *)toggle {HaloTouchSettings.shared.invertLook=toggle.on;[self saveSettings];}
- (void)floatingChanged:(UISwitch *)toggle {HaloTouchSettings.shared.floatingStick=toggle.on;[self saveSettings];}
- (void)hapticsChanged:(UISwitch *)toggle {
    HaloTouchSettings.shared.haptics=toggle.on;
    if(toggle.on) host_ios_haptics_tap();
    [self saveSettings];
}
- (void)namesChanged:(UISwitch *)toggle {
    HaloTouchSettings.shared.showNames=toggle.on;
    [self.controls applySettings];
    [self saveSettings];
}
- (void)styleChanged:(UISegmentedControl *)control {
    [HaloTouchSettings.shared applyStyle:control.selectedSegmentIndex==1];
    [self.controls applySettings];
    [self rebuildIcons];
    [self saveSettings];
}
- (void)resetLayout {
    if(!self.resetArmed) {
        /* A second tap confirms, so a stray tap can't undo a layout. */
        self.resetArmed=YES;
        [self.resetButton setTitle:@"Tap Again to Reset Layout" forState:UIControlStateNormal];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            self.resetArmed=NO;
            [self.resetButton setTitle:@"Reset Layout" forState:UIControlStateNormal];
        });
        return;
    }
    self.resetArmed=NO;
    [self.resetButton setTitle:@"Reset Layout" forState:UIControlStateNormal];
    /* positions, sizes and icons go back to the current style's defaults */
    [HaloTouchSettings.shared resetLayout];
    [self.controls applySettings];
    [self selectControl:-1];
    [self saveSettings];
}
- (void)crouchChanged:(UISwitch *)toggle {HaloTouchSettings.shared.toggleCrouch=toggle.on;[self saveSettings];}
- (void)menuButtonsChanged:(UISwitch *)toggle {HaloTouchSettings.shared.menuButtons=toggle.on;[self saveSettings];}
- (void)showDebugMenu {
    if(self.debugMenu) return;
    HaloDebugMenu *menu=[[HaloDebugMenu alloc] initWithFrame:self.panel.frame];
    __weak HaloControlEditor *weakSelf=self;
    menu.onClose=^{
        HaloControlEditor *editor=weakSelf;
        [editor.debugMenu removeFromSuperview];
        editor.debugMenu=nil;
        editor.panel.hidden=NO;
    };
    menu.onPlay=^{
        [weakSelf.controls finishEditing];
    };
    self.debugMenu=menu;
    self.panel.hidden=YES;
    [self addSubview:menu];
    [self setNeedsLayout];
}
- (void)done {
    [self.controls finishEditing];
}
@end
