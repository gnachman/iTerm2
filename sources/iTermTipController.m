//
//  iTermTipController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipController.h"
#import "iTermTipWindowController.h"

static NSString *const kUnshowableTipsKey = @"NoSyncTipsToNotShow";
static NSString *const kLastTipTimeKey = @"NoSyncLastTipTime";

static NSString *const kTipTitle = @"title";
static NSString *const kTipBody = @"body";
static NSString *const kTipURL = @"url";

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
        self.tips = @{ @"Tip 1": @{ kTipTitle: @"Title 1",
                                    kTipBody: @"Body 1",
                                    kTipURL: @"http://google.com/" },
                       @"Tip 2": @{ kTipTitle: @"Title 2",
                                    kTipBody: @"Body 2",
                                    kTipURL: @"http://yahoo.com/" } };
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
    NSArray *unshowableTips = [[NSUserDefaults standardUserDefaults] objectForKey:kUnshowableTipsKey];
    for (NSString *tipKey in _tips) {
        if (![unshowableTips containsObject:tipKey]) {
            return tipKey;
        }
    }
    return nil;
}

- (void)showTipForKey:(NSString *)tipKey {
    NSDictionary *tip = _tips[tipKey];
    _showingTip = YES;
    [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate]
                                              forKey:kLastTipTimeKey];
    self.currentTipName = tipKey;
    iTermTipWindowController *window = [[iTermTipWindowController alloc] initWithTitle:tip[kTipTitle]
                                                                                  body:tip[kTipBody]
                                                                                   url:tip[kTipURL]];
    window.delegate = self;
}

#pragma mark - iTermTipWindowDelegate

- (void)tipWindowDismissed {
    _showingTip = NO;
    NSArray *unshowableTips = [[NSUserDefaults standardUserDefaults] objectForKey:kUnshowableTipsKey];
    if (!unshowableTips) {
        unshowableTips = @[];
    }
    unshowableTips = [unshowableTips arrayByAddingObject:_currentTipName];
    [[NSUserDefaults standardUserDefaults] setObject:unshowableTips forKey:kUnshowableTipsKey];
}

- (void)tipWindowPostponed {
    _showingTip = NO;
}

@end
