#import "iTermPreviousState.h"

#import "DebugLogging.h"
#import "iTermController.h"
#import "PseudoTerminal.h"

@implementation iTermPreviousState

- (instancetype)init {
    self = [super init];
    if (self) {
        NSDictionary *activeAppDict = [[NSWorkspace sharedWorkspace] activeApplication];
        DLog(@"Active app is %@", activeAppDict);
        if ([[activeAppDict objectForKey:@"NSApplicationBundleIdentifier"] isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
            self.previouslyActiveAppPID = nil;
        } else {
            self.previouslyActiveAppPID = activeAppDict[@"NSApplicationProcessIdentifier"];
        }
        _itermWasActiveWhenHotkeyOpened = [NSApp isActive];
    }
    return self;
}

- (void)restorePreviouslyActiveApp {
    if (!_previouslyActiveAppPID) {
        return;
    }
    
    NSRunningApplication *app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:[_previouslyActiveAppPID intValue]];
    
    if (app) {
        DLog(@"Restore app %@", app);
        [app activateWithOptions:0];
    }
    self.previouslyActiveAppPID = nil;
}

- (void)restore {
    [self restorePreviouslyActiveApp];
    if (!self.itermWasActiveWhenHotkeyOpened) {
        // TODO: This is weird. What is its purpose? After I fix the bug where non-hotkey windows
        // get ordered front is this still necessary?
        [NSApp hide:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(),
                       ^{
                           [NSApp unhideWithoutActivation];
                           for (PseudoTerminal *terminal in [[iTermController sharedInstance] terminals]) {
                               if (![terminal isHotKeyWindow]) {
                                   [[[terminal window] animator] setAlphaValue:1];
                               }
                           }
                       });
    } else {
        PseudoTerminal *currentTerm = [[iTermController sharedInstance] currentTerminal];
        if (currentTerm && ![currentTerm isHotKeyWindow] && [currentTerm fullScreen]) {
            [currentTerm hideMenuBar];
        } else {
            [currentTerm showMenuBar];
        }
    }
}

- (void)suppressHideApp {
    self.itermWasActiveWhenHotkeyOpened = YES;
}

- (NSInteger)indexOfFrontNonHotKeyTerminal {
    if (![NSApp isActive]) {
        return -1;
    }
    
    __block NSInteger result = -1;
    [[[iTermController sharedInstance] terminals] enumerateObjectsUsingBlock:^(PseudoTerminal *_Nonnull term,
                                                                               NSUInteger idx,
                                                                               BOOL *_Nonnull stop) {
        if (!term.isHotKeyWindow && [[term window] isKeyWindow]) {
            result = idx;
        }
    }];
    
    return result;
}

@end
