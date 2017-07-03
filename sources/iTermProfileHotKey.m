#import "iTermProfileHotKey.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "NSArray+iTerm.h"
#import "NSScreen+iTerm.h"
#import "PseudoTerminal.h"
#import "SolidColorView.h"
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSUInteger, iTermAnimationDirection) {
    kAnimationDirectionDown,
    kAnimationDirectionRight,
    kAnimationDirectionLeft,
    kAnimationDirectionUp
};

static iTermAnimationDirection iTermAnimationDirectionOpposite(iTermAnimationDirection direction) {
    switch (direction) {
        case kAnimationDirectionRight:
            return kAnimationDirectionLeft;
        case kAnimationDirectionLeft:
            return kAnimationDirectionRight;
        case kAnimationDirectionDown:
            return kAnimationDirectionUp;
        case kAnimationDirectionUp:
            return kAnimationDirectionDown;
    }
    assert(false);
}
static NSString *const kGUID = @"GUID";
static NSString *const kArrangement = @"Arrangement";

@interface iTermProfileHotKey()
@property(nonatomic, copy) NSString *profileGuid;
@property(nonatomic, retain) NSDictionary *restorableState;
@property(nonatomic, readwrite) BOOL rollingIn;
@property(nonatomic) BOOL birthingWindow;
@property(nonatomic, retain) NSWindowController *windowControllerBeingBorn;
@end

@implementation iTermProfileHotKey {
    BOOL _activationPending;
}

- (instancetype)initWithShortcuts:(NSArray<iTermShortcut *> *)shortcuts
          hasModifierActivation:(BOOL)hasModifierActivation
             modifierActivation:(iTermHotKeyModifierActivation)modifierActivation
                        profile:(Profile *)profile {
    self = [super initWithShortcuts:shortcuts
              hasModifierActivation:hasModifierActivation
                 modifierActivation:modifierActivation];

    if (self) {
        _allowsStateRestoration = YES;
        _profileGuid = [profile[KEY_GUID] copy];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(terminalWindowControllerCreated:)
                                                     name:kTerminalWindowControllerWasCreatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_restorableState release];
    [_profileGuid release];
    [_windowController release];
    [_windowControllerBeingBorn release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p shortcuts=%@ hasModAct=%@ modAct=%@ profile.name=%@ profile.guid=%@ open=%@>",
            [self class], self, self.shortcuts,
            @(self.hasModifierActivation), @(self.modifierActivation),
            self.profile[KEY_NAME], self.profile[KEY_GUID], @(self.isHotKeyWindowOpen)];
}

#pragma mark - APIs

- (Profile *)profile {
    return [[ProfileModel sharedInstance] bookmarkWithGuid:_profileGuid];
}

- (void)createWindow {
    [self createWindowWithURL:nil];
}

- (void)createWindowWithURL:(NSURL *)url {
    if (self.windowController.weaklyReferencedObject) {
        return;
    }

    DLog(@"Create new window controller for profile hotkey");
    PseudoTerminal *windowController = [self windowControllerFromRestorableState];
    if (windowController) {
        if (url) {
            [[iTermController sharedInstance] launchBookmark:self.profile
                                                  inTerminal:windowController
                                                     withURL:url.absoluteString
                                            hotkeyWindowType:[self hotkeyWindowType]
                                                     makeKey:YES
                                                 canActivate:YES
                                                     command:nil
                                                       block:nil];
        }
    } else {
        windowController = [self windowControllerFromProfile:[self profile] url:url];
    }
    [_windowController release];
    _windowController = nil;
    self.windowController = [windowController weakSelf];
}

- (void)setWindowController:(PseudoTerminal<iTermWeakReference> *)windowController {
    // Since this is public and we don't want to accidentally change an
    // existing window controller, we assert that it's nil. This complicates
    // internal calls, unfortunately, but better to catch the bugs.
    assert(!_windowController.weaklyReferencedObject);
    
    [_windowController release];
    _windowController = [windowController.weakSelf retain];
    if (!_windowController.weaklyReferencedObject) {
        return;
    }

    if (self.floats) {
        _windowController.window.level = NSStatusWindowLevel;
    } else {
        _windowController.window.level = NSNormalWindowLevel;
    }
    _windowController.hotkeyWindowType = [self hotkeyWindowType];

    [_windowController.window setAlphaValue:0];
    if (_windowController.windowType != WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        [_windowController.window setCollectionBehavior:self.windowController.window.collectionBehavior & ~NSWindowCollectionBehaviorFullScreenPrimary];
    }
}

- (NSPoint)destinationPointForInitialPoint:(NSPoint)point
              forAnimationInDirection:(iTermAnimationDirection)direction
                                 size:(NSSize)size {
    switch (direction) {
        case kAnimationDirectionUp:
            return NSMakePoint(point.x, point.y + size.height);
        case kAnimationDirectionDown:
            return NSMakePoint(point.x, point.y - size.height);
        case kAnimationDirectionLeft:
            return NSMakePoint(point.x - size.width, point.y);
        case kAnimationDirectionRight:
            return NSMakePoint(point.x + size.width, point.y);
    }
    assert(false);
}

- (NSRect)preferredFrameForWindowController:(PseudoTerminal<iTermWeakReference> *)windowController {
    // This can be the anchored screen (typically the screen the window was created
    // with, but can be changed by -moveToPreferredScreen). If unanchored, then
    // it is the current screen.
    NSScreen *screen = windowController.screen;

    switch (windowController.windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
        case WINDOW_TYPE_LION_FULL_SCREEN:
            return [windowController canonicalFrameForScreen:screen];

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            return [self frameByMovingFrame:windowController.window.frame
                                 fromScreen:windowController.window.screen
                                   toScreen:screen];
    }
    assert(false);
}

- (NSRect)frameByMovingFrame:(NSRect)sourceFrame fromScreen:(NSScreen *)sourceScreen toScreen:(NSScreen *)destinationScreen {
    NSSize originOffset = NSMakeSize(sourceFrame.origin.x - sourceScreen.visibleFrame.origin.x,
                                     sourceFrame.origin.y - sourceScreen.visibleFrame.origin.y);

    NSRect destination = sourceFrame;
    destination.origin = destinationScreen.visibleFrame.origin;
    destination.origin.x += originOffset.width;
    destination.origin.y += originOffset.height;
    return destination;
}

- (NSPoint)hiddenOriginForScreen:(NSScreen *)screen {
    NSRect rect = self.windowController.window.frame;
    DLog(@"Basing hidden origin on screen frame (IHD) %@", NSStringFromRect(screen.visibleFrameIgnoringHiddenDock));
    switch (self.windowController.windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
            return NSMakePoint(rect.origin.x, NSMaxY(screen.visibleFrame));
            
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
            return NSMakePoint(NSMinX(screen.visibleFrameIgnoringHiddenDock), rect.origin.y);
            
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            return NSMakePoint(NSMaxX(screen.visibleFrameIgnoringHiddenDock), rect.origin.y);
            
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            return NSMakePoint(rect.origin.x, NSMinY(screen.visibleFrameIgnoringHiddenDock) - NSHeight(rect));
            
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            return [self frameByMovingFrame:rect fromScreen:self.windowController.window.screen toScreen:screen].origin;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
            return screen.frame.origin;

        case WINDOW_TYPE_LION_FULL_SCREEN:
            return rect.origin;
    }
    return rect.origin;
}

- (BOOL)rect:(NSRect)rect intersectsAnyScreenExcept:(NSScreen *)allowedScreen {
    return [[NSScreen screens] anyWithBlock:^BOOL(NSScreen *screen) {
        if (screen == allowedScreen) {
            return NO;
        }
        NSRect screenFrame = screen.frame;
        return NSIntersectsRect(rect, screenFrame);
    }];
}

- (void)rollInAnimatingInDirection:(iTermAnimationDirection)direction {
    [self moveToPreferredScreen];
    self.windowController.window.alphaValue = 0;

    NSRect destination = [self preferredFrameForWindowController:self.windowController];
    NSRect proposedHiddenRect = self.windowController.window.frame;
    proposedHiddenRect.origin = [self hiddenOriginForScreen:self.windowController.screen];
    if ([self rect:proposedHiddenRect intersectsAnyScreenExcept:self.windowController.window.screen]) {
        [self.windowController.window setFrame:destination display:YES];
    } else {
        [self.windowController.window setFrameOrigin:proposedHiddenRect.origin];
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        [context setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
        [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
        [self.windowController.window.animator setFrame:destination display:NO];
        [self.windowController.window.animator setAlphaValue:1];
    }
                        completionHandler:^{
                            [self rollInFinished];
                        }];
}

- (void)rollOutAnimatingInDirection:(iTermAnimationDirection)direction {
    _activationPending = NO;
    NSRect source = self.windowController.window.frame;
    NSRect destination = source;
    destination.origin = [self hiddenOriginForScreen:self.windowController.window.screen];

    if ([self rect:destination intersectsAnyScreenExcept:self.windowController.window.screen]) {
        destination = source;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        [context setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
        [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
        [self.windowController.window.animator setFrame:destination display:NO];
        [self.windowController.window.animator setAlphaValue:0];
    }
                        completionHandler:^{
                            [self didFinishRollingOut];
                        }];

}

- (void)moveToPreferredScreen {
    // If the window was created with a profile that moved it to the screen
    // with the cursor, anchor it to the screen that currently has the cursor.
    // Doing so changes what -[PseudoTerminal screen] returns. If any other
    // screen preference was selected this does nothing.
    [self.windowController moveToPreferredScreen];

    NSRect destination = [self preferredFrameForWindowController:self.windowController];
    [self.windowController.window setFrame:destination display:NO];
}

- (void)fadeIn {
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [self rollInFinished];
    }];
    [[self.windowController.window animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
}

- (void)fadeOut {
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [self didFinishRollingOut];
    }];
    self.windowController.window.animator.alphaValue = 0;
    [NSAnimationContext endGrouping];
}

- (iTermAnimationDirection)animateInDirectionForWindowType:(iTermWindowType)windowType {
    switch (windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
            return kAnimationDirectionDown;
            break;
            
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
            return kAnimationDirectionRight;
            break;
            
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            return kAnimationDirectionLeft;
            break;
            
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            return kAnimationDirectionUp;
            break;
            
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
        case WINDOW_TYPE_LION_FULL_SCREEN:
            assert(false);
    }
}

- (BOOL)floats {
    return [iTermProfilePreferences boolForKey:KEY_HOTKEY_FLOAT inProfile:self.profile];
}

- (void)rollInAnimated:(BOOL)animated {
    DLog(@"Roll in [show] hotkey window");
    if (_rollingIn) {
        DLog(@"Already rolling in");
        return;
    }
    if (_rollingOut) {
        DLog(@"Rolling out. Cancel roll in");
        return;
    }
    _rollingIn = YES;
    if (self.hotkeyWindowType != iTermHotkeyWindowTypeFloatingPanel) {
        DLog(@"Activate iTerm2 prior to animating hotkey window in");
        _activationPending = YES;
        [NSApp activateIgnoringOtherApps:YES];
    }
    [self.windowController.window makeKeyAndOrderFront:nil];
    if (animated) {
        switch (self.windowController.windowType) {
            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_RIGHT_PARTIAL:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_BOTTOM_PARTIAL:
                [self rollInAnimatingInDirection:[self animateInDirectionForWindowType:self.windowController.windowType]];
                break;
                
            case WINDOW_TYPE_NORMAL:
            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
                [self moveToPreferredScreen];
                [self fadeIn];
                break;
                
            case WINDOW_TYPE_LION_FULL_SCREEN:
                assert(false);
        }
    } else {
        [self moveToPreferredScreen];
        self.windowController.window.alphaValue = 1;
        [self rollInFinished];
    }
}

- (void)rollOut {
    DLog(@"Roll out [hide] hotkey window");
    if (_rollingOut) {
        DLog(@"Already rolling out");
        return;
    }
    // Note: the test for alpha is because when you become an LSUIElement, the
    // window's alpha could be 1 but it's still invisible.
    if (self.windowController.window.alphaValue == 0) {
        DLog(@"RollOutHotkeyTerm returning because term isn't visible.");
        return;
    }

    _rollingOut = YES;

    if ([iTermProfilePreferences boolForKey:KEY_HOTKEY_ANIMATE inProfile:self.profile]) {
        switch (self.windowController.windowType) {
            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_RIGHT_PARTIAL:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_BOTTOM_PARTIAL: {
                iTermAnimationDirection inDirection = [self animateInDirectionForWindowType:self.windowController.windowType];
                iTermAnimationDirection outDireciton = iTermAnimationDirectionOpposite(inDirection);
                [self rollOutAnimatingInDirection:outDireciton];
                break;
            }
                
            case WINDOW_TYPE_NORMAL:
            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
                [self fadeOut];
                break;
                
            case WINDOW_TYPE_LION_FULL_SCREEN:
                assert(false);
        }
    } else {
        self.windowController.window.alphaValue = 0;
        [self didFinishRollingOut];
    }
}

- (void)saveHotKeyWindowState {
    if (self.windowController.weaklyReferencedObject && self.profileGuid) {
        DLog(@"Saving hotkey window state for %@", self);
        BOOL includeContents = [iTermAdvancedSettingsModel restoreWindowContents];
        NSDictionary *arrangement = [self.windowController arrangementExcludingTmuxTabs:YES
                                                                      includingContents:includeContents];
        if (arrangement) {
            self.restorableState = @{ kGUID: self.profileGuid,
                                      kArrangement: arrangement };
        } else {
            self.restorableState = nil;
        }
    } else if ([iTermController sharedInstance]) {
        DLog(@"Not saving hotkey window state for %@", self);
        self.restorableState = nil;
    }
}

- (void)setLegacyState:(NSDictionary *)state {
    if (self.profileGuid && state) {
        self.restorableState = @{ kGUID: self.profileGuid,
                                  kArrangement: state };
    } else {
        DLog(@"Not setting legacy state. profileGuid=%@, state=%@", self.profileGuid, state);
    }
}

- (BOOL)loadRestorableStateFromArray:(NSArray *)states {
    for (NSDictionary *state in states) {
        if ([state[kGUID] isEqualToString:self.profileGuid]) {
            self.restorableState = state;
            return YES;
        }
    }
    return NO;
}

- (BOOL)isHotKeyWindowOpen {
    return self.windowController.window.alphaValue > 0;
}

- (void)revealForScripting {
    [self showHotKeyWindow];
}

- (void)hideForScripting {
    [self hideHotKeyWindowAnimated:YES suppressHideApp:NO otherIsRollingIn:NO];
}

- (void)toggleForScripting {
    if (self.isRevealed) {
        [self hideForScripting];
    } else {
        [self revealForScripting];
    }
}

- (BOOL)isRevealed {
    return self.windowController.window.alphaValue == 1 && self.windowController.window.isVisible;
}

- (void)cancelRollOut {
    DLog(@"cancelRollOut requested");
    if (_rollOutCancelable && _rollingOut) {
        DLog(@"Cancelling roll out");
        _rollingOut = NO;
        _rollOutCancelable = NO;
        [self orderOut];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_activationPending && ![NSApp isActive]) {
                [NSApp activateIgnoringOtherApps:YES];
            }
        });
    } else {
        DLog(@"Cannot cancel. cancelable=%@ rollingOut=%@", @(_rollOutCancelable), @(_rollingOut));
    }
}

#pragma mark - Protected

- (NSArray<iTermBaseHotKey *> *)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)genericSiblings {
    DLog(@"hotKeypressedWithSiblings called on %@ with siblings %@", self, genericSiblings);

    genericSiblings = [genericSiblings arrayByAddingObject:self];

    NSArray<iTermProfileHotKey *> *siblings = [genericSiblings mapWithBlock:^id(iTermBaseHotKey *anObject) {
        if ([anObject isKindOfClass:[iTermProfileHotKey class]]) {
            return anObject;
        } else {
            return nil;
        }
    }];
    // If any sibling is rolling out but we can cancel the rollout, do so. This is after the window
    // has finished animating out but we're in the delay period before activating the app the user
    // was in before pressing the hotkey to reveal the hotkey window.
    for (iTermProfileHotKey *other in siblings) {
        if (other.rollingOut && other.rollOutCancelable) {
            [other cancelRollOut];
        }
    }
    // If any sibling is rolling in or rolling out, do nothing. This keeps us from ending up in
    // a broken state where some siblings are in and others are out.
    BOOL anyTransitioning = [siblings anyWithBlock:^BOOL(iTermProfileHotKey *other) {
        BOOL result = other.rollingIn || other.rollingOut;
        if (result) {
            DLog(@"Found a transitioning sibling: %@ rollingIn=%@ rollingOut=%@", other, @(other.rollingIn), @(other.rollingOut));
        }
        return result;
    }];
    if (anyTransitioning) {
        DLog(@"One or more siblings is transitioning so I'm returning without doing anything.");
        return siblings;
    }
    DLog(@"toggle window %@. siblings=%@", self, siblings);
    BOOL allSiblingsOpen = [siblings allWithBlock:^BOOL(iTermProfileHotKey *sibling) {
        iTermProfileHotKey *other = (iTermProfileHotKey *)sibling;
        return other.isHotKeyWindowOpen;
    }];

    BOOL anyIsKey = [siblings anyWithBlock:^BOOL(iTermProfileHotKey *anObject) {
        return anObject.windowController.window.isKeyWindow;
    }];

    DLog(@"Hotkey pressed. All open=%@  any is key=%@  siblings=%@",
         @(allSiblingsOpen), @(anyIsKey), siblings);
    for (iTermProfileHotKey *sibling in [NSSet setWithArray:[siblings arrayByAddingObject:self]]) {
        DLog(@"Invoking handleHotkeyPressWithAllOpen:%@ anyIsKey:%@ on %@", @(allSiblingsOpen), @(anyIsKey), sibling);
        [sibling handleHotkeyPressWithAllOpen:allSiblingsOpen anyIsKey:anyIsKey];
    }
    return siblings;
}

- (void)handleHotkeyPressWithAllOpen:(BOOL)allSiblingsOpen anyIsKey:(BOOL)anyIsKey {
    if (self.windowController.weaklyReferencedObject) {
        DLog(@"already have a hotkey window created");
        if (self.windowController.window.alphaValue == 1) {
            if (self.windowController.openInCurrentSpace && !self.windowController.window.isOnActiveSpace) {
                DLog(@"Move already-open hotkey window to current space");
                NSWindow *window = self.windowController.window;
                // I tested this on 10.12 and it's sufficient to move the window. Maybe not in older OS versions?
                NSWindowCollectionBehavior collectionBehavior = window.collectionBehavior;
                window.collectionBehavior = (collectionBehavior | NSWindowCollectionBehaviorCanJoinAllSpaces);
                window.collectionBehavior = collectionBehavior;
                return;
            }
            DLog(@"hotkey window opaque");
            if (!allSiblingsOpen) {
                DLog(@"Not all siblings open. Doing nothing.");
                return;
            }
            self.wasAutoHidden = NO;
            if (anyIsKey || ![self switchToVisibleHotKeyWindowIfPossible]) {
                DLog(@"Hide hotkey window");
                [self hideHotKeyWindowAnimated:YES suppressHideApp:NO otherIsRollingIn:NO];
            }
        } else {
            DLog(@"hotkey window not opaque");
            [self showHotKeyWindow];
        }
    } else {
        DLog(@"no hotkey window created yet");
        [self showHotKeyWindow];
    }
}

#pragma mark - Private

- (PseudoTerminal *)windowControllerFromRestorableState {
    NSDictionary *arrangement = [[self.restorableState[kArrangement] copy] autorelease];
    self.restorableState = nil;
    if (!arrangement) {
        return nil;
    }

    PseudoTerminal *term = [PseudoTerminal terminalWithArrangement:arrangement
                                          forceOpeningHotKeyWindow:NO];
    if (term) {
        [[iTermController sharedInstance] addTerminalWindow:term];
    }
    return term;
}

- (iTermHotkeyWindowType)hotkeyWindowType {
    if (self.floats) {
        if ([iTermProfilePreferences intForKey:KEY_SPACE inProfile:self.profile] == iTermProfileJoinsAllSpaces) {
            // This makes it possible to overlap Lion fullscreen windows.
            return iTermHotkeyWindowTypeFloatingPanel;
        } else {
            return iTermHotkeyWindowTypeFloatingWindow;
        }
    } else {
        return iTermHotkeyWindowTypeRegular;
    }
}

- (PseudoTerminal *)windowControllerFromProfile:(Profile *)hotkeyProfile url:(NSURL *)url {
    if (!hotkeyProfile) {
        return nil;
    }
    if ([[hotkeyProfile objectForKey:KEY_WINDOW_TYPE] intValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
        // Lion fullscreen doesn't make sense with hotkey windows. Change
        // window type to traditional fullscreen.
        NSMutableDictionary *replacement = [[hotkeyProfile mutableCopy] autorelease];
        replacement[KEY_WINDOW_TYPE] = @(WINDOW_TYPE_TRADITIONAL_FULL_SCREEN);
        hotkeyProfile = replacement;
    }
    [self.delegate hotKeyWillCreateWindow:self];
    self.birthingWindow = YES;
    PTYSession *session = [[iTermController sharedInstance] launchBookmark:hotkeyProfile
                                                                inTerminal:nil
                                                                   withURL:url.absoluteString
                                                          hotkeyWindowType:[self hotkeyWindowType]
                                                                   makeKey:YES
                                                               canActivate:YES
                                                                   command:nil
                                                                     block:nil];
    self.birthingWindow = NO;

    [self.delegate hotKeyDidCreateWindow:self];
    PseudoTerminal *result = nil;
    if (session) {
        result = [[iTermController sharedInstance] terminalWithSession:session];
    }
    self.windowControllerBeingBorn = nil;
    return result;
}

- (void)rollInFinished {
    DLog(@"Roll-in finished for %@", self);
    _rollingIn = NO;
    [self.windowController.window makeKeyAndOrderFront:nil];
    [self.windowController.window makeFirstResponder:self.windowController.currentSession.textview];
    [[self.windowController currentTab] recheckBlur];
}

- (void)didFinishRollingOut {
    DLog(@"didFinishRollingOut");
    _activationPending = NO;
    DLog(@"Invoke willFinishRollingOutProfileHotKey:");
    BOOL activatingOtherApp = [self.delegate willFinishRollingOutProfileHotKey:self];
    if (activatingOtherApp) {
        _rollOutCancelable = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_rollingOut) {
                _rollOutCancelable = NO;
                [self orderOut];
            }
        });
    } else {
        [self orderOut];
    }
}

- (void)orderOut {
    DLog(@"Call orderOut: on terminal %@", self.windowController);
    [self.windowController.window orderOut:self];
    DLog(@"Returned from orderOut:. Set _rollingOut=NO");
    
    // This must be done after orderOut: so autoHideHotKeyWindowsExcept: will know to throw out the
    // previous state.
    _rollingOut = NO;
}

- (BOOL)autoHides {
    return [iTermProfilePreferences boolForKey:KEY_HOTKEY_AUTOHIDE inProfile:self.profile];
}

- (void)setAutoHides:(BOOL)autoHides {
    [iTermProfilePreferences setBool:autoHides
                              forKey:KEY_HOTKEY_AUTOHIDE
                           inProfile:self.profile
                               model:[ProfileModel sharedInstance]];
}

// If there's a visible hotkey window that is either not key or is on another space, switch to it.
// Save the previously active app unless switching spaces (why the exception? Not sure.)
// Return YES if it was switched to, or NO if the window isn't suitable for switching to.
- (BOOL)switchToVisibleHotKeyWindowIfPossible {
    DLog(@"switchToVisibleHotKeyWindowIfPossible");
    const BOOL activateStickyHotkeyWindow = (!self.autoHides &&
                                             !self.windowController.window.isKeyWindow);
    if (activateStickyHotkeyWindow && ![NSApp isActive]) {
        DLog(@"Storing previously active app");
        [self.delegate storePreviouslyActiveApp:self];
    }
    const BOOL hotkeyWindowOnOtherSpace = ![self.windowController.window isOnActiveSpace];
    if (hotkeyWindowOnOtherSpace || activateStickyHotkeyWindow) {
        DLog(@"Hotkey window is active on another space, or else it doesn't autohide but isn't key. Switch to it.");
        if (self.hotkeyWindowType != iTermHotkeyWindowTypeFloatingPanel) {
            [NSApp activateIgnoringOtherApps:YES];
        }
        [self.windowController.window makeKeyAndOrderFront:nil];
        return YES;
    } else {
        return NO;
    }
}

- (void)showAlreadyVisibleHotKeyWindow {
    DLog(@"showAlreadyVisibleHotKeyWindow");
    if (![self switchToVisibleHotKeyWindowIfPossible]) {
        DLog(@"Make window key, make textview first responder.");
        [self.windowController.window makeKeyAndOrderFront:nil];
        [self.windowController.window makeFirstResponder:self.windowController.currentSession.textview];
    }
}

- (void)showHotKeyWindow {
    [self showHotKeyWindowCreatingWithURLIfNeeded:nil];
}

- (BOOL)showHotKeyWindowCreatingWithURLIfNeeded:(NSURL *)url {
    DLog(@"showHotKeyWindow: %@", self);
    
    if (self.windowController.window.alphaValue == 1 && self.windowController.window.isVisible) {
        // This path is taken when you use a session hotkey to navigate to an already-open hotkey window.
        [self showAlreadyVisibleHotKeyWindow];
        return NO;
    }
    [self.delegate storePreviouslyActiveApp:self];

    BOOL result = NO;
    if (!self.windowController.weaklyReferencedObject) {
        DLog(@"Create new hotkey window");
        [self createWindowWithURL:url];
        result = YES;
    }
    [self rollInAnimated:[iTermProfilePreferences boolForKey:KEY_HOTKEY_ANIMATE inProfile:self.profile]];
    return result;
}

- (void)hideHotKeyWindowAnimated:(BOOL)animated
                 suppressHideApp:(BOOL)suppressHideApp
                otherIsRollingIn:(BOOL)otherIsRollingIn {
    DLog(@"Hide hotkey window. animated=%@ suppressHideApp=%@", @(animated), @(suppressHideApp));

    if (suppressHideApp) {
        [self.delegate suppressHideApp];
    }
    if (!animated) {
        [self fastHideHotKeyWindow];
    }

    for (NSWindow *sheet in self.windowController.window.sheets) {
        [self.windowController.window endSheet:sheet];
    }
    self.closedByOtherHotkeyWindowOpening = otherIsRollingIn;
    [self rollOut];
}

- (void)windowWillClose {
    [_windowController release];
    _windowController = nil;
    self.restorableState = nil;
}

- (void)fastHideHotKeyWindow {
    DLog(@"fastHideHotKeyWindow");
    [self.windowController.window orderOut:nil];
    self.windowController.window.alphaValue = 0;
}

#pragma mark - Notifications

- (void)terminalWindowControllerCreated:(NSNotification *)notification {
    if (self.birthingWindow) {
        self.windowControllerBeingBorn = notification.object;
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    _activationPending = NO;
}
@end
