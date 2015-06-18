//
//  iTermTipController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipController.h"

#import "iTermTip.h"
#import "iTermTipWindowController.h"

static NSString *const kUnshowableTipsKey = @"NoSyncTipsToNotShow";
static NSString *const kLastTipTimeKey = @"NoSyncLastTipTime";
static NSString *const kTipsDisabledKey = @"NoSyncTipsDisabled";

@interface iTermTipController()<iTermTipWindowDelegate>
@property(nonatomic, retain) NSDictionary *tips;
@property(nonatomic, copy) NSString *currentTipName;
@end

#define ALWAYS_SHOW_TIP 1

@implementation iTermTipController {
    BOOL _showingTip;
}

+ (instancetype)sharedInstance {
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
        self.tips = @{ @"Tip 1": @{ kTipTitleKey: @"Shell Integration",
                                    kTipBodyKey: @"The Shell Integration feature puts a blue arrow next to your shell prompt that turns red if the command fails.",
                                    kTipUrlKey: @"http://google.com/" },
                       @"Tip 2": @{ kTipTitleKey: @"Title 2",
                                    kTipBodyKey: @"Body 2",
                                    kTipUrlKey: @"http://yahoo.com/" },
                       @"Tip 3": @{ kTipTitleKey: @"Title 3",
                                    kTipBodyKey: @"Body 3",
                                    kTipUrlKey: @"http://yahoo.com/" },
                       @"Tip 4": @{ kTipTitleKey: @"Title 4",
                                    kTipBodyKey: @"Body 4",
                                    kTipUrlKey: @"http://yahoo.com/" },
                       @"Tip 5": @{ kTipTitleKey: @"Title 5",
                                    kTipBodyKey: @"Body 5",
                                    kTipUrlKey: @"http://yahoo.com/" },
                       };
    }
    return self;
}

- (void)dealloc {
    [_tips release];
    [_currentTipName release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching {
    [self tryToShowTip];
}

- (void)tryToShowTip {
#if ALWAYS_SHOW_TIP
    [self showTipForKey:self.tips.allKeys.firstObject];
    return;
#endif

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kTipsDisabledKey]) {
        return;
    }
    if (_showingTip || [self haveShownTipRecently]) {
        [self performSelector:@selector(tryToShowTip) withObject:nil afterDelay:3600 * 24];
        return;
    }
    NSString *nextTipKey = [self nextTipKey];
    if (nextTipKey) {
        [self showTipForKey:nextTipKey];
        [self performSelector:@selector(tryToShowTip) withObject:nil afterDelay:3600 * 24];
    }
}

- (BOOL)haveShownTipRecently {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval previous = [[NSUserDefaults standardUserDefaults] doubleForKey:kLastTipTimeKey];
    return (now - previous) < 24 * 3600;
}

- (NSString *)nextTipKey {
    return [self tipKeyAfter:nil];
}

- (NSString *)tipKeyAfter:(NSString *)prev {
    NSArray *unshowableTips = [[NSUserDefaults standardUserDefaults] objectForKey:kUnshowableTipsKey];
#if ALWAYS_SHOW_TIP
    unshowableTips = @[];
#endif
    BOOL okToReturn = (prev == nil);
    for (NSString *tipKey in _tips) {
        if (okToReturn && ![unshowableTips containsObject:tipKey]) {
            return tipKey;
        }
        if (!okToReturn) {
            okToReturn = [tipKey isEqualToString:prev];
        }
    }
    return nil;
}

- (void)showTipForKey:(NSString *)tipKey {
    NSDictionary *tipDictionary = _tips[tipKey];
    [self willShowTipWithIdentifier:tipKey];
    iTermTip *tip = [[[iTermTip alloc] initWithDictionary:tipDictionary
                                               identifier:tipKey] autorelease];
    iTermTipWindowController *controller = [[iTermTipWindowController alloc] initWithTip:tip];
    controller.delegate = self;
    // Cause it to load and become visible.
    [controller window];
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
}

- (iTermTip *)tipWindowTipAfterTipWithIdentifier:(NSString *)previousId {
    NSString *identifier = [self tipKeyAfter:previousId];
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

@end
