//
//  iTermTipController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipController.h"
#import <Cocoa/Cocoa.h>

#import "iTermAdvancedSettingsModel.h"
#import "iTermTip.h"
#import "iTermTipData.h"
#import "iTermTipWindowController.h"
#import "NSApplication+iTerm.h"

static NSString *const kUnshowableTipsKey = @"NoSyncTipsToNotShow";
static NSString *const kLastTipTimeKey = @"NoSyncLastTipTime";
static NSString *const kTipsDisabledKey = @"NoSyncTipsDisabled";  // There's an advanced pref with the same name.
static const NSTimeInterval kSecondsPerDay = 24 * 60 * 60;
static NSString *const kTimeOfFirstLaunchOfVersionWithTip = @"NoSyncTimeOfFirstLaunchOfVersionWithTip";
static NSString *const kPermissionToShowTip = @"NoSyncPermissionToShowTip";
static const NSTimeInterval kMinDelayBeforeAskingForPermission = 2 * kSecondsPerDay;

@interface iTermTipController()<iTermTipWindowDelegate>
@property(nonatomic, retain) NSDictionary *tips;
@property(nonatomic, copy) NSString *currentTipName;
@end

#define ALWAYS_SHOW_TIP 0

@implementation iTermTipController {
    BOOL _showingTip;
}

+ (instancetype)sharedInstance {
    // The tip of the day code uses sizeThatFits:, which is only available in 10.10.
    // It also does a lot of other stuff that doesn't work on older versions for annoying and
    // complex reasons. In the interest of getting this out in the world quickly I'm going to
    // limit the feature's availability to 10.10 and up because it's not critical. If it's
    // worthwhile I can always make a simpler version for users on older OS versions. Over 80%
    // of users on 2.1.1 are running 10.10.
    if (![[NSControl class] instancesRespondToSelector:@selector(sizeThatFits:)]) {
        return nil;
    }
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        return nil;
    }
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.tips = [iTermTipData allTips];
    }
    return self;
}

- (void)dealloc {
    [_tips release];
    [_currentTipName release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)applicationDidFinishLaunching {
    // This must be done before the delay. If it's called at the wrong time while a window is
    // becoming fullscreen, the app becomes unresponsive to mouse and keyboard events. Issue 4775.
    [self askForPermissionIfNeeded];

    // Wait until startup activity has settled down so there's enough CPU for the animation to
    // look good.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{
                       [self tryToShowTip];
                       
                       [[NSNotificationCenter defaultCenter] addObserver:self
                                                                selector:@selector(applicationDidBecomeActive:)
                                                                    name:NSApplicationDidBecomeActiveNotification
                                                                  object:nil];
                   });
}

- (void)askForPermissionIfNeeded {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval timeOfFirstLaunchOfVersionWithTip =
        [[NSUserDefaults standardUserDefaults] doubleForKey:kTimeOfFirstLaunchOfVersionWithTip];
    if (!timeOfFirstLaunchOfVersionWithTip) {
        [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
                                                  forKey:kTimeOfFirstLaunchOfVersionWithTip];
    } else {
        if (![self haveAskedForPermission] &&
            now - timeOfFirstLaunchOfVersionWithTip > kMinDelayBeforeAskingForPermission &&
            ![[NSUserDefaults standardUserDefaults] boolForKey:kTipsDisabledKey]) {
            [self askForPermission];
        }
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self tryToShowTip];
}

- (BOOL)havePermission {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPermissionToShowTip];
}

- (BOOL)haveAskedForPermission {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kPermissionToShowTip] != nil;
}

- (void)askForPermission {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"See Tips of the Day?";
    alert.informativeText = @"iTerm2 can show you a Tip of the Day message to help you learn about its many features. Are you interested?";
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    BOOL havePermission = ([alert runModal] == NSAlertFirstButtonReturn);
    [[NSUserDefaults standardUserDefaults] setBool:havePermission forKey:kPermissionToShowTip];
}

- (void)tryToShowTip {
#if ALWAYS_SHOW_TIP
    [self showTipForKey:[[self.tips.allKeys sortedArrayUsingSelector:@selector(compare:)] firstObject]];
    return;
#endif
    if (![self havePermission]) {
        return;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kTipsDisabledKey]) {
        return;
    }
    if (![[NSApplication sharedApplication] isActive]) {
        return;
    }
    if (_showingTip || [self haveShownTipRecently]) {
        [self performSelector:@selector(tryToShowTip) withObject:nil afterDelay:[self timeBetweenTips]];
        return;
    }
    NSString *nextTipKey = [self nextTipKey];
    if (nextTipKey) {
        [self showTipForKey:nextTipKey];
        [self performSelector:@selector(tryToShowTip) withObject:nil afterDelay:[self timeBetweenTips]];
    }
}

- (void)showTip {
    if (_showingTip) {
        return;
    }

    // Try to show the last-seen tip.
    NSArray *unshowableTips = [[NSUserDefaults standardUserDefaults] objectForKey:kUnshowableTipsKey];
    NSString *key = [unshowableTips lastObject];
    if (!key) {
        // You've never seen it before? Then show the first one.
        key = [self nextTipKey];
    }
    if (key) {  // Key should always be non-nil, but better be safe.
        [self showTipForKey:key];
    }
}

- (BOOL)haveShownTipRecently {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval previous = [[NSUserDefaults standardUserDefaults] doubleForKey:kLastTipTimeKey];
    return (now - previous) < [self timeBetweenTips];
}

- (NSString *)nextTipKey {
    return [self tipKeyAfter:nil respectUnshowable:YES];
}

- (NSString *)tipKeyAfter:(NSString *)prev respectUnshowable:(BOOL)respectUnshowable {
    NSArray *unshowableTips = [[NSUserDefaults standardUserDefaults] objectForKey:kUnshowableTipsKey];
#if ALWAYS_SHOW_TIP
    unshowableTips = @[];
#endif
    if (!respectUnshowable) {
        unshowableTips = @[];
    }
    BOOL okToReturn = (prev == nil);
    for (NSString *tipKey in [[_tips allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if (okToReturn && ![unshowableTips containsObject:tipKey]) {
            return tipKey;
        }
        if (!okToReturn) {
            okToReturn = [tipKey isEqualToString:prev];
        }
    }
    return nil;
}

- (NSString *)tipKeyBefore:(NSString *)successor {
    NSArray *keys = [[_tips allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger index = [keys indexOfObject:successor];
    if (index == 0 || index == NSNotFound) {
        return nil;
    }
    return keys[index - 1];
}

- (void)showTipForKey:(NSString *)tipKey {
    NSDictionary *tipDictionary = _tips[tipKey];
    [self willShowTipWithIdentifier:tipKey];
    iTermTip *tip = [[[iTermTip alloc] initWithDictionary:tipDictionary
                                               identifier:tipKey] autorelease];
    iTermTipWindowController *controller = [[[iTermTipWindowController alloc] initWithTip:tip] autorelease];
    controller.delegate = self;
    // Cause it to load and become visible.
    [controller showTipWindow];
}

- (void)willShowTipWithIdentifier:(NSString *)tipKey {
    _showingTip = YES;
    [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
                                              forKey:kLastTipTimeKey];
    self.currentTipName = tipKey;
}

- (void)doNotShowCurrentTipAgain {
    NSArray *unshowableTips = [[NSUserDefaults standardUserDefaults] objectForKey:kUnshowableTipsKey];
    if (!unshowableTips) {
        unshowableTips = @[];
    }
    unshowableTips = [unshowableTips arrayByAddingObject:_currentTipName];
    [[NSUserDefaults standardUserDefaults] setObject:unshowableTips forKey:kUnshowableTipsKey];
}

#pragma mark - iTermTipWindowDelegate

- (void)tipWindowDismissed {
    _showingTip = NO;
    [self doNotShowCurrentTipAgain];
}

- (void)tipWindowPostponed {
    _showingTip = NO;
}

- (void)tipWindowRequestsDisable {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kTipsDisabledKey];
    _showingTip = NO;
}

- (void)tipWindowRequestsEnable {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kTipsDisabledKey];
}

- (BOOL)tipWindowTipsAreDisabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kTipsDisabledKey];
}

- (iTermTip *)tipWindowTipAfterTipWithIdentifier:(NSString *)previousId {
    NSString *identifier = [self tipKeyAfter:previousId respectUnshowable:NO];
    if (!identifier) {
        return nil;
    } else {
        return [[[iTermTip alloc] initWithDictionary:_tips[identifier]
                                          identifier:identifier] autorelease];
    }
}

- (iTermTip *)tipWindowTipBeforeTipWithIdentifier:(NSString *)previousId {
    NSString *identifier = [self tipKeyBefore:previousId];
    if (!identifier) {
        return nil;
    } else {
        return [[[iTermTip alloc] initWithDictionary:_tips[identifier]
                                          identifier:identifier] autorelease];
    }
}

- (void)tipWindowWillShowTipWithIdentifier:(NSString *)identifier {
    [self doNotShowCurrentTipAgain];
    [self willShowTipWithIdentifier:identifier];
}

- (NSTimeInterval)timeBetweenTips {
    return [iTermAdvancedSettingsModel timeBetweenTips];
}

- (BOOL)tipFrequencyIsHigh {
    return [self timeBetweenTips] <= kSecondsPerDay;
}

- (void)toggleTipFrequency {
    if ([self tipFrequencyIsHigh]) {
        [iTermAdvancedSettingsModel setTimeBetweenTips:kSecondsPerDay * 7];
    } else {
        [iTermAdvancedSettingsModel setTimeBetweenTips:kSecondsPerDay];
    }
}

@end
