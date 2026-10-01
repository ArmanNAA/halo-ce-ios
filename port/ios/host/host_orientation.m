#import "host_orientation.h"
#include "ios_host.h"

/* SDL 3.4.16 owns these controllers. These categories add only orientation
   preferences inherited from UIKit, never replace SDL's own methods. Recheck
   the selectors when upgrading SDL; no runtime class mutation is needed. */
@interface SDL_uikitviewcontroller : UIViewController
@end
@interface SDLLaunchScreenController : UIViewController
@end
@interface SDLUIKitSceneDelegate : NSObject <UIWindowSceneDelegate>
@end

/* Set while an iPad turns between its two landscape orientations. */
static BOOL flipping_landscape;

static BOOL landscape_lock(UIViewController *controller) {
    /* An iPhone turns freely between its two landscape orientations, as other
       landscape apps do, so the picture and the home gesture follow the phone;
       its orientation masks keep it out of portrait. The lock is for iPadOS 26
       and later, whose full-screen scenes would otherwise turn upright. */
    if (UIDevice.currentDevice.userInterfaceIdiom!=UIUserInterfaceIdiomPad || flipping_landscape) return NO;
    /* Don't lock a transient portrait scene before the geometry request has
       completed. The scene callback updates this preference after rotation. */
    return UIInterfaceOrientationIsLandscape(controller.viewIfLoaded.window.windowScene.interfaceOrientation);
}

static void update_orientation_lock(UIWindowScene *scene) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0,*)) {
        for (UIWindow *window in scene.windows) {
            UIViewController *controller=window.rootViewController;
            while (controller.presentedViewController) controller=controller.presentedViewController;
            [controller setNeedsUpdateOfPrefersInterfaceOrientationLocked];
        }
    }
#else
    (void)scene;
#endif
}

/* A locked iPad stays in the landscape orientation it started in. When it is
   turned the other way up, unlock it for the turn and lock it again after. */
static void follow_ipad_landscape_flips(UIWindow *window) {
    static BOOL following;
    if (following || UIDevice.currentDevice.userInterfaceIdiom!=UIUserInterfaceIdiomPad) return;
    following=YES;
    __weak UIWindow *weakWindow=window;
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        (void)note;
        UIDeviceOrientation device=UIDevice.currentDevice.orientation;
        UIWindowScene *scene=weakWindow.windowScene;
        if (!scene || !UIDeviceOrientationIsLandscape(device) || flipping_landscape) return;
        /* The device turned left shows the interface turned right. */
        UIInterfaceOrientation wanted=device==UIDeviceOrientationLandscapeLeft?
            UIInterfaceOrientationLandscapeRight:UIInterfaceOrientationLandscapeLeft;
        if (scene.interfaceOrientation==wanted) return;
        flipping_landscape=YES;
        update_orientation_lock(scene);
        UIInterfaceOrientationMask mask=wanted==UIInterfaceOrientationLandscapeRight?
            UIInterfaceOrientationMaskLandscapeRight:UIInterfaceOrientationMaskLandscapeLeft;
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask]
            errorHandler:^(NSError *error) {
            host_logf(HOST_LOG_WARN,"landscape flip request: %s",error.localizedDescription.UTF8String);
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(700*NSEC_PER_MSEC)),dispatch_get_main_queue(),^{
            flipping_landscape=NO;
            update_orientation_lock(scene);
        });
    }];
}

#define HALO_LANDSCAPE_PREFERENCES \
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; } \
- (BOOL)prefersInterfaceOrientationLocked { return landscape_lock(self); }

@implementation HaloLandscapeController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
HALO_LANDSCAPE_PREFERENCES
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    host_ios_require_landscape(self.view.window);
}
@end

@implementation HaloLandscapeDocumentPicker
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
HALO_LANDSCAPE_PREFERENCES
@end

@implementation SDL_uikitviewcontroller (HaloLandscape)
HALO_LANDSCAPE_PREFERENCES
@end

@implementation SDLLaunchScreenController (HaloLandscape)
HALO_LANDSCAPE_PREFERENCES
@end

@implementation SDLUIKitSceneDelegate (HaloLandscape)
/* iPadOS 27 consults the scene delegate in preference to Info.plist. */
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)scene {
    (void)scene;
    return UIInterfaceOrientationMaskLandscape;
}
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
- (void)windowScene:(UIWindowScene *)scene didUpdateEffectiveGeometry:(UIWindowSceneGeometry *)previousGeometry API_AVAILABLE(ios(26.0)) {
    BOOL wasLandscape=UIInterfaceOrientationIsLandscape(previousGeometry.interfaceOrientation);
    BOOL isLandscape=UIInterfaceOrientationIsLandscape(scene.effectiveGeometry.interfaceOrientation);
    if (wasLandscape != isLandscape) update_orientation_lock(scene);
    CGSize size=scene.effectiveGeometry.coordinateSpace.bounds.size;
    host_logf(HOST_LOG_INFO,"scene geometry %.0fx%.0f orientation=%ld locked=%d",
        size.width,size.height,(long)scene.effectiveGeometry.interfaceOrientation,
        scene.effectiveGeometry.isInterfaceOrientationLocked);
}
#endif
@end

void host_ios_require_landscape(UIWindow *window) {
    if (!window) return;
    follow_ipad_landscape_flips(window);
    [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0,*)) [window.rootViewController setNeedsUpdateOfPrefersInterfaceOrientationLocked];
#endif
    UIWindowSceneGeometryPreferencesIOS *geometry=[[UIWindowSceneGeometryPreferencesIOS alloc]
        initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
    [window.windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(NSError *error) {
        host_logf(HOST_LOG_WARN,"landscape request: %s",error.localizedDescription.UTF8String);
    }];
}
