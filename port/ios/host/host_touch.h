/* Touch controls shared between the in-game overlay (host_touch.m), its
   layout editor (host_touch_editor.m) and haptics (host_haptics.m). */
#pragma once
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, HaloControlKind) {
    HaloControlKindButton,   /* an SDL gamepad button */
    HaloControlKindTrigger,  /* an SDL trigger axis, fully pressed or released */
    HaloControlKindStick,    /* an SDL stick; input is its X axis, Y follows */
};

typedef NS_ENUM(NSInteger, HaloAnchor) {
    HaloAnchorBottomLeft,
    HaloAnchorBottomRight,
    HaloAnchorTopLeft,
    HaloAnchorTopCenter,
};

typedef struct {
    const char *ident;         /* stable key in Documents/controls.json */
    const char *name;          /* shown in the editor */
    const char *text;          /* the label in text mode */
    const char *badge;         /* the controller letter shown on face buttons, or NULL */
    const char *accessibility;
    HaloControlKind kind;
    int input;
    CGFloat size;              /* diameter in points before scaling */
    HaloAnchor anchor;
    CGFloat dx, dy;            /* centre offset inward from the anchor, in points before scaling */
    BOOL hidden;               /* hidden by default */
    BOOL aim;                  /* dragging while held turns the view, by default */
    const char *icons;         /* comma-separated SF Symbols; the first is the default */
} HaloControlSpec;

/* Indices into halo_control_specs, in table order. */
enum {
    HaloControlMove,
    HaloControlLook,
    HaloControlFire,
    HaloControlGrenade,
    HaloControlJump,
    HaloControlMelee,
    HaloControlReload,
    HaloControlWeapon,
    HaloControlCrouch,
    HaloControlZoom,
    HaloControlFlashlight,
    HaloControlSwapGrenade,
    HaloControlPause,
    HaloControlBack,
    HaloControlUp,
    HaloControlDown,
    HaloControlLeft,
    HaloControlRight,
    HaloControlCount
};

extern const HaloControlSpec halo_control_specs[HaloControlCount];

/* The SF Symbols offered for a control, in order; empty for the sticks. */
NSArray<NSString *> *halo_control_icons(int index);

@interface HaloControlState : NSObject
@property(nonatomic) BOOL placed;            /* moved by the player: x and y apply */
@property(nonatomic) CGFloat x, y;           /* centre as a fraction of the layout area */
@property(nonatomic) CGFloat scale;          /* size multiplier */
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL aim;
@property(nonatomic, copy) NSString *icon;   /* "sf:<symbol>", "text" or "custom" */
@end

@interface HaloTouchSettings : NSObject
@property(nonatomic) CGFloat lookSensitivity;
@property(nonatomic) CGFloat opacity;
@property(nonatomic) BOOL invertLook;
@property(nonatomic) BOOL floatingStick;
@property(nonatomic) BOOL haptics;
@property(nonatomic) BOOL showNames;
@property(nonatomic) BOOL protectExit;       /* swipe twice to leave the app */
@property(nonatomic, readonly) NSArray<HaloControlState *> *controls;
+ (instancetype)shared;
- (void)save;
- (void)resetLayout;
- (NSString *)customIconPath:(int)index;
/* The control's icon, or nil when it shows text. */
- (UIImage *)imageForControl:(int)index pointSize:(CGFloat)pointSize;
@end

@class HaloControlEditor;

@interface HaloControls : UIView
@property(nonatomic, weak, readonly) HaloControlEditor *editor;
- (CGRect)layoutRect;
- (CGFloat)layoutScale;
- (UIView *)viewForControl:(int)index;
/* Re-read icons, sizes, visibility and opacity from the settings. */
- (void)applySettings;
- (void)finishEditing;
@end

@interface HaloControlEditor : UIView
- (instancetype)initWithControls:(HaloControls *)controls;
@end

void host_ios_haptics_rumble(float intensity);
void host_ios_haptics_tap(void);
void host_ios_haptics_stop(void);
void host_ios_apply_exit_gesture(void);
