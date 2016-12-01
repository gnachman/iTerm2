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
        DLog(@"Previously active pid for %p is %@", self, _previouslyActiveAppPID);
        _itermWasActiveWhenHotkeyOpened = [NSApp isActive];
    }
    return self;
}

- (void)dealloc {
    [_owner release];
    [super dealloc];
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
    DLog(@"Restore %p with previously active app %@", self, _previouslyActiveAppPID);
    [self restorePreviouslyActiveApp];
    if (self.itermWasActiveWhenHotkeyOpened) {
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
