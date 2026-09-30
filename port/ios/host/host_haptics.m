/* Game rumble and button taps on the phone's Taptic Engine. The game sets the
   touch controller's motors (host_touch.m); a looping continuous haptic plays
   while they turn, at their strength. iPads and other devices without a
   Taptic Engine skip all of this. */
#import <UIKit/UIKit.h>
#import <CoreHaptics/CoreHaptics.h>
#include "ios_host.h"
#import "host_touch.h"

static CHHapticEngine *engine;
static id<CHHapticAdvancedPatternPlayer> player;
static BOOL playing, engine_failed;
static UIImpactFeedbackGenerator *tap_generator;

/* Rumble weaker than this is not felt; stop instead of buzzing faintly. */
static const float rumble_floor=.04f;

static BOOL haptics_supported(void) {
    static int supported=-1;
    if(supported<0) supported=CHHapticEngine.capabilitiesForHardware.supportsHaptics?1:0;
    return supported==1;
}

static void on_main(dispatch_block_t block) {
    if(NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(),block);
}

/* The engine stops when the app is suspended or the audio server resets;
   the player is made again the next time the game rumbles. */
static void forget_player(void) {
    player=nil;
    playing=NO;
}

static BOOL prepare_player(void) {
    if(player) return YES;
    if(engine_failed || !haptics_supported()) return NO;
    NSError *error=nil;
    if(!engine) {
        engine=[[CHHapticEngine alloc] initAndReturnError:&error];
        if(!engine) {
            engine_failed=YES;
            host_logf(HOST_LOG_WARN,"haptics unavailable: %s",error.localizedDescription.UTF8String);
            return NO;
        }
        engine.playsHapticsOnly=YES;
        engine.stoppedHandler=^(CHHapticEngineStoppedReason reason) {
            (void)reason;
            dispatch_async(dispatch_get_main_queue(),^{forget_player();});
        };
        engine.resetHandler=^{
            dispatch_async(dispatch_get_main_queue(),^{forget_player();});
        };
    }
    if(![engine startAndReturnError:&error]) {
        host_logf(HOST_LOG_WARN,"haptics engine did not start: %s",error.localizedDescription.UTF8String);
        return NO;
    }
    CHHapticEventParameter *intensity=[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:1];
    CHHapticEventParameter *sharpness=[[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:.3f];
    CHHapticEvent *event=[[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
        parameters:@[intensity,sharpness] relativeTime:0 duration:30];
    CHHapticPattern *pattern=[[CHHapticPattern alloc] initWithEvents:@[event] parameters:@[] error:&error];
    id<CHHapticAdvancedPatternPlayer> created=pattern?[engine createAdvancedPlayerWithPattern:pattern error:&error]:nil;
    if(!created) {
        host_logf(HOST_LOG_WARN,"haptics player: %s",error.localizedDescription.UTF8String);
        return NO;
    }
    created.loopEnabled=YES;
    player=created;
    playing=NO;
    return YES;
}

static void stop_rumble(void) {
    if(player && playing) [player stopAtTime:CHHapticTimeImmediate error:NULL];
    playing=NO;
}

void host_ios_haptics_rumble(float intensity) {
    on_main(^{
        if(!HaloTouchSettings.shared.haptics || intensity<rumble_floor) {stop_rumble();return;}
        if(!prepare_player()) return;
        CHHapticDynamicParameter *level=[[CHHapticDynamicParameter alloc]
            initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl value:fminf(1,intensity) relativeTime:0];
        NSError *error=nil;
        if(![player sendParameters:@[level] atTime:CHHapticTimeImmediate error:&error]) {forget_player();return;}
        if(!playing) {
            if([player startAtTime:CHHapticTimeImmediate error:&error]) playing=YES;
            else forget_player();
        }
    });
}

void host_ios_haptics_stop(void) {
    on_main(^{stop_rumble();});
}

void host_ios_haptics_tap(void) {
    on_main(^{
        if(!HaloTouchSettings.shared.haptics) return;
        if(!tap_generator) tap_generator=[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [tap_generator impactOccurredWithIntensity:.7];
        [tap_generator prepare];
    });
}
