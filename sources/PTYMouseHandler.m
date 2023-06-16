//
//  PTYMouseHandler.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/20.
//

#import "PTYMouseHandler.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAltScreenMouseScrollInferrer.h"
#import "iTermController.h"
#import "iTermImageInfo.h"
#import "iTermMouseReportingFrustrationDetector.h"
#import "iTermPreferences.h"
#import "iTermSelection.h"
#import "iTermSelectionScrollHelper.h"
#import "iTermSwipeTracker.h"
#import "NSEvent+iTerm.h"
#import "ThreeFingerTapGestureRecognizer.h"

// Minimum distance that the mouse must move before a cmd+drag will be
// recognized as a drag.
static const int kDragThreshold = 3;

static const NSUInteger kDragPaneModifiers = (NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift);
static const NSUInteger kRectangularSelectionModifiers = (NSEventModifierFlagCommand | NSEventModifierFlagOption);
static const NSUInteger kRectangularSelectionModifierMask = (kRectangularSelectionModifiers | NSEventModifierFlagControl);

static double Square(double n) {
    return n * n;
}

static double EuclideanDistance(NSPoint p1, NSPoint p2) {
    return sqrt(Square(p1.x - p2.x) + Square(p1.y - p2.y));
}

@interface PTYMouseHandler()<iTermAltScreenMouseScrollInferrerDelegate, iTermSwipeTrackerDelegate>
@end

@implementation PTYMouseHandler {
    // The most recent mouse-down was a "first mouse" (activated the window).
    BOOL _mouseDownWasFirstMouse;

    // Saves the monotonically increasing event number of a first-mouse click, which disallows
    // selection.
    NSInteger _firstMouseEventNumber;

    // Last mouse down was on already-selected text?
    BOOL _lastMouseDownOnSelectedText;

    PointerController *pointer_;

    // If true, ignore the next mouse up because it's due to a three finger
    // mouseDown.
    BOOL _mouseDownIsThreeFingerClick;

    BOOL _mouseDown;
    BOOL _mouseDragged;
    BOOL _mouseDownOnSelection;
    BOOL _mouseDownOnImage;
    id<iTermImageInfoReading>_imageBeingClickedOn;
    NSEvent *_mouseDownEvent;

    // Work around an embarassing macOS bug. Issue 8350.
    BOOL _makingThreeFingerSelection;

    iTermSelectionScrollHelper *_selectionScrollHelper;
    iTermMouseReportingFrustrationDetector *_mouseReportingFrustrationDetector;

    // Works around an apparent OS bug where we get drag events without a mousedown.
    BOOL dragOk_;

    BOOL _committedToDrag;

    // Detects when the user is trying to scroll in alt screen with the scroll wheel.
    iTermAltScreenMouseScrollInferrer *_altScreenMouseScrollInferrer;

    ThreeFingerTapGestureRecognizer *_threeFingerTapGestureRecognizer;

    BOOL _haveSeenScrollWheelEvent;

    iTermSwipeTracker *_swipeTracker;
    BOOL _scrolling;

    // If mouse reporting was off when momentum scrolling began, the rest of the momentum scroll
    // should not be reported. Issue 10960.
    BOOL _disableScrollReportingUntilMomentumEnds;
}

- (instancetype)initWithSelectionScrollHelper:(iTermSelectionScrollHelper *)selectionScrollHelper
              threeFingerTapGestureRecognizer:(ThreeFingerTapGestureRecognizer *)threeFingerTapGestureRecognizer
                    pointerControllerDelegate:(id<PointerControllerDelegate>)pointerControllerDelegate
    mouseReportingFrustrationDetectorDelegate:(id<iTermMouseReportingFrustrationDetectorDelegate>)mouseReportingFrustrationDetectorDelegate {
    self = [super init];
    if (self) {
        _firstMouseEventNumber = -1;
        _semanticHistoryDragged = NO;
        _selectionScrollHelper = selectionScrollHelper;
        _altScreenMouseScrollInferrer = [[iTermAltScreenMouseScrollInferrer alloc] init];
        _altScreenMouseScrollInferrer.delegate = self;
        _threeFingerTapGestureRecognizer = threeFingerTapGestureRecognizer;
        pointer_ = [[PointerController alloc] init];
        pointer_.delegate = pointerControllerDelegate;
        _mouseReportingFrustrationDetector = [[iTermMouseReportingFrustrationDetector alloc] init];
        _mouseReportingFrustrationDetector.delegate = mouseReportingFrustrationDetectorDelegate;
        _swipeTracker = [[iTermSwipeTracker alloc] init];
        _swipeTracker.delegate = self;
    }
    return self;
}

#pragma mark - Left mouse

- (void)mouseDown:(NSEvent *)event superCaller:(void (^)(void))superCaller {
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    if ([_threeFingerTapGestureRecognizer mouseDown:event]) {
        return;
    }
    DLog(@"Mouse Down on %@ with event %@, num touches=%d", self, event, self.numTouches);
    iTermClickSideEffects sideEffects = iTermClickSideEffectsNone;
    if ([self mouseDownImpl:event sideEffects:&sideEffects]) {
        superCaller();
    }
    if (sideEffects != iTermClickSideEffectsIgnore) {
        [self setMouseInfoForEvent:event
                       sideEffects:sideEffects];
    }
}

// This is an API. Internal calls should all go through the two-argument method. Because clicks can
// be directed to SessionView (or at least could many years ago!) this must be a first-class citizen.
- (BOOL)mouseDownImpl:(NSEvent *)event {
    iTermClickSideEffects sideEffects = iTermClickSideEffectsNone;
    const BOOL result = [self mouseDownImpl:event sideEffects:&sideEffects];
    if (sideEffects != iTermClickSideEffectsIgnore) {
        [self setMouseInfoForEvent:event
                       sideEffects:sideEffects];
    }
    return result;
}

// Returns yes if [super mouseDown:event] should be run by caller.
- (BOOL)mouseDownImpl:(NSEvent *)event
          sideEffects:(iTermClickSideEffects *)sideEffects {
    DLog(@"mouseDownImpl: called");
    _mouseDownWasFirstMouse = ([event eventNumber] == _firstMouseEventNumber) || ![NSApp keyWindow];
    _lastMouseDownOnSelectedText = NO;  // This may get updated to YES later.
    const BOOL altPressed = ([event it_modifierFlags] & NSEventModifierFlagOption) != 0;
    BOOL cmdPressed = ([event it_modifierFlags] & NSEventModifierFlagCommand) != 0;
    const BOOL shiftPressed = ([event it_modifierFlags] & NSEventModifierFlagShift) != 0;
    const BOOL ctrlPressed = ([event it_modifierFlags] & NSEventModifierFlagControl) != 0;
    if (gDebugLogging && altPressed && cmdPressed && shiftPressed && ctrlPressed) {
        // Dump view hierarchy
        DLog(@"Beep: dump view hierarchy");
        NSBeep();
        [[iTermController sharedInstance] dumpViewHierarchy];
        *sideEffects = iTermClickSideEffectsIgnore;
        return NO;
    }
    const BOOL isFocused = [self.mouseDelegate mouseHandlerViewHasFocus:self];
    if (!isFocused &&
        !cmdPressed &&
        [iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse]) {
        // Clicking in an inactive pane with focus follows mouse makes it active.
        // Because of how FFM works, this would only happen if another app were key.
        // See issue 3163.
        DLog(@"Click on inactive pane with focus follows mouse");
        _mouseDownWasFirstMouse = YES;
        [self.mouseDelegate mouseHandlerMakeFirstResponder:self];
        *sideEffects = iTermClickSideEffectsIgnore;
        return NO;
    }
    if (_mouseDownWasFirstMouse &&
        !cmdPressed &&
        ![iTermAdvancedSettingsModel alwaysAcceptFirstMouse]) {
        // A click in an inactive window without cmd pressed by default just brings the window
        // to the fore and takes no additional action. If you enable alwaysAcceptFirstMouse then
        // it is treated like a normal click (issue 3236). Returning here prevents mouseDown=YES
        // which keeps -mouseUp from doing anything such as changing first responder.
        DLog(@"returning because this was a first-mouse event.");
        *sideEffects = iTermClickSideEffectsIgnore;
        return NO;
    }
    if (_numTouches == 3 && _makingThreeFingerSelection) {
        DLog(@"Ignore mouse down because you're making a three finger selection");
        *sideEffects = iTermClickSideEffectsIgnore;
        return NO;
    }
    [pointer_ notifyLeftMouseDown];
    _mouseDownIsThreeFingerClick = NO;
    DLog(@"mouseDownImpl - set mouseDownIsThreeFingerClick=NO");
    if (([event it_modifierFlags] & kDragPaneModifiers) == kDragPaneModifiers) {
        [self.mouseDelegate mouseHandlerWillBeginDragPane:self];
        DLog(@"Returning because of drag starting");
        *sideEffects = iTermClickSideEffectsIgnore;
        return NO;
    }
    if (_numTouches == 3) {
        // NOTE! If you turn on the following setting:
        //   System Preferences > Accessibility > Mouse & Trackpad > Trackpad Options... > Enable dragging > three finger drag
        // Then a three-finger drag gets translated into mouseDown:…mouseDragged:…mouseUp:.
        // Prior to commit 96323ddf8 we didn't track touch-up/touch-down unless necessary, so that
        // feature worked unless you had a mouse gesture that caused touch tracking to be enabled.
        // In issue 8321 it was revealed that touch tracking breaks three-finger drag. The solution
        // is to not return early if we detect a three-finger down but don't have a pointer action
        // for it. Then it proceeds to behave like before commit 96323ddf8. Otherwise, it'll just
        // watch for the actions that three-finger touches can cause.
        BOOL shouldReturnEarly = YES;
        if ([iTermPreferences boolForKey:kPreferenceKeyThreeFingerEmulatesMiddle]) {
            [self emulateThirdButtonPressDown:YES withEvent:event];
            *sideEffects = iTermClickSideEffectsIgnore;
        } else {
            // Perform user-defined gesture action, if any
            shouldReturnEarly = [pointer_ mouseDown:event
                                        withTouches:_numTouches
                                       ignoreOption:[self terminalWantsMouseReports]];
            if (shouldReturnEarly) {
                *sideEffects |= iTermClickSideEffectsPerformBoundAction;
            }
            DLog(@"Set mouseDown=YES because of 3 finger mouseDown (not emulating middle)");
            _mouseDown = YES;
        }
        DLog(@"Returning because of 3-finger click.");
        if (shouldReturnEarly) {
            return NO;
        }
    }
    if ([pointer_ eventEmulatesRightClick:event]) {
        const BOOL performed = [pointer_ mouseDown:event
                                       withTouches:_numTouches
                                      ignoreOption:[self terminalWantsMouseReports]];
        if (performed) {
            *sideEffects |= iTermClickSideEffectsPerformBoundAction;
        }
        DLog(@"Returning because emulating right click.");
        return NO;
    }

    dragOk_ = YES;
    _committedToDrag = NO;
    if (cmdPressed) {
        if (![self.mouseDelegate mouseHandlerViewHasFocus:self]) {
            if (![self.mouseDelegate mouseHandlerIsInKeyWindow:self]) {
                // A cmd-click in in inactive window makes the pane active.
                DLog(@"Cmd-click in inactive window");
                _mouseDownWasFirstMouse = YES;
                [self.mouseDelegate mouseHandlerMakeFirstResponder:self];
                DLog(@"Returning because of cmd-click in inactive window.");
                *sideEffects = iTermClickSideEffectsIgnore;
                return NO;
            }
        } else if (![self.mouseDelegate mouseHandlerIsInKeyWindow:self]) {
            // A cmd-click in an active session in a non-key window acts like a click without cmd.
            // This can be changed in advanced settings so cmd-click will still invoke semantic
            // history even for non-key windows.
            DLog(@"Cmd-click in active session in non-key window");
            cmdPressed = [iTermAdvancedSettingsModel cmdClickWhenInactiveInvokesSemanticHistory];
        }
    }
    if (([event it_modifierFlags] & kDragPaneModifiers) == kDragPaneModifiers) {
        DLog(@"Returning because of drag modifiers.");
        *sideEffects = iTermClickSideEffectsIgnore;
        return YES;
    }

    const VT100GridCoord clickPointCoord = [self.mouseDelegate mouseHandler:self
                                                                 clickPoint:event
                                                              allowOverflow:YES];
    const int x = clickPointCoord.x;
    const int y = clickPointCoord.y;
    if ([self.mouseDelegate mouseHandler:self coordIsMutable:VT100GridCoordMake(x, y)] &&
        [self reportMouseDrags]) {
        [_selectionScrollHelper disableUntilMouseUp];
    }
    if (_numTouches <= 1) {
        [self.mouseDelegate mouseHandlerDidSingleClick:self];
    }

    DLog(@"Set mouseDown=YES.");
    _mouseDown = YES;

    [_mouseReportingFrustrationDetector mouseDown:event
                                         reported:[self mouseEventIsReportable:event]];
    if ([self reportMouseEvent:event]) {
        DLog(@"Returning because mouse event reported.");
        [self.selection clearSelection];
        *sideEffects = iTermClickSideEffectsModifySelection;
        return NO;
    }

    id<iTermImageInfoReading> const imageBeingClickedOn = [self.mouseDelegate mouseHandler:self imageAt:VT100GridCoordMake(x, y)];
    const long long overflow = [_mouseDelegate mouseHandlerTotalScrollbackOverflow:self];
    const BOOL mouseDownOnSelection =
        [self.selection containsAbsCoord:VT100GridAbsCoordMake(x, y + overflow)];
    _lastMouseDownOnSelectedText = mouseDownOnSelection;

    if (!_mouseDownWasFirstMouse) {
        [self.mouseDelegate mouseHandlerLockScrolling:self];

        if (event.clickCount == 1 && !cmdPressed && !shiftPressed && !imageBeingClickedOn && !mouseDownOnSelection) {
            [self.selection clearSelection];
            *sideEffects |= iTermClickSideEffectsModifySelection;
        }
    }

    _mouseDownEvent = event;
    _mouseDragged = NO;
    _mouseDownOnSelection = NO;
    _mouseDownOnImage = NO;

    const int clickCount = [event clickCount];
    DLog(@"clickCount=%d altPressed=%d cmdPressed=%d", clickCount, (int)altPressed, (int)cmdPressed);
    const BOOL isExtension = ([self.selection hasSelection] && shiftPressed);
    if (isExtension && [self.selection hasSelection]) {
        if (!self.selection.live) {
            [self.selection beginExtendingSelectionAt:VT100GridAbsCoordMake(x, y + overflow)];
            *sideEffects |= iTermClickSideEffectsModifySelection;
        }
    } else if (clickCount < 2) {
        // single click
        iTermSelectionMode mode;
        if ((event.it_modifierFlags & kRectangularSelectionModifierMask) == kRectangularSelectionModifiers) {
            mode = kiTermSelectionModeBox;
        } else {
            mode = kiTermSelectionModeCharacter;
        }

        if (imageBeingClickedOn) {
            _imageBeingClickedOn = imageBeingClickedOn;
            _mouseDownOnImage = YES;
            self.selection.appending = NO;
        } else if (mouseDownOnSelection) {
            // not holding down shift key but there is an existing selection.
            // Possibly a drag coming up (if a cmd-drag follows)
            DLog(@"mouse down on selection, returning");
            _mouseDownOnSelection = YES;
            self.selection.appending = NO;
            return YES;
        } else {
            // start a new selection
            [self.selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(x, y + overflow)
                                                mode:mode
                                              resume:NO
                                              append:(cmdPressed && !altPressed)];
            self.selection.resumable = YES;
        }
    } else if ([self shouldSelectWordWithClicks:clickCount]) {
        [self.selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(x, y + overflow)
                                            mode:kiTermSelectionModeWord
                                          resume:YES
                                          append:self.selection.appending];
        *sideEffects |= iTermClickSideEffectsModifySelection;
    } else if (clickCount == 3) {
        BOOL wholeLines =
        [iTermPreferences boolForKey:kPreferenceKeyTripleClickSelectsFullWrappedLines];
        iTermSelectionMode mode =
        wholeLines ? kiTermSelectionModeWholeLine : kiTermSelectionModeLine;

        [self.selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(x, y + overflow)
                                            mode:mode
                                          resume:YES
                                          append:self.selection.appending];
        *sideEffects |= iTermClickSideEffectsModifySelection;
    } else if ([self shouldSmartSelectWithClicks:clickCount]) {
        [self.selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(x, y + overflow)
                                            mode:kiTermSelectionModeSmart
                                          resume:YES
                                          append:self.selection.appending];
        *sideEffects |= iTermClickSideEffectsModifySelection;
    }

    DLog(@"Mouse down. selection set to %@", self.selection);
    [self.mouseDelegate mouseHandlerDidMutateState:self];

    DLog(@"Reached end of mouseDownImpl.");
    return NO;
}

- (void)mouseUp:(NSEvent *)event {
    const iTermClickSideEffects sideEffects = [self mouseUpImpl:event];
    if (sideEffects != iTermClickSideEffectsIgnore) {
        [self setMouseInfoForEvent:event
                       sideEffects:sideEffects];
    }
}

- (iTermClickSideEffects)mouseUpImpl:(NSEvent *)event {
    DLog(@"Mouse Up on %@ with event %@, numTouches=%d, mouseDown=%@", self, event, _numTouches, @(_mouseDown));
    _makingThreeFingerSelection = NO;
    DLog(@"_makingThreeFingerSelection <- NO");
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    if ([_threeFingerTapGestureRecognizer mouseUp:event]) {
        return iTermClickSideEffectsNone;
    }
    int numTouches = _numTouches;
    _numTouches = 0;
    _firstMouseEventNumber = -1;  // Synergy seems to interfere with event numbers, so reset it here.
    DLog(@"Set firstMouseEventNumber to -1 on mouseUp");
    if (_mouseDownIsThreeFingerClick) {
        [self emulateThirdButtonPressDown:NO withEvent:event];
        DLog(@"Returning from mouseUp because mouse-down was a 3-finger click");
        if (self.selection.live) {
            [self copyAfterSelectionEndsIfDesired];
        }
        [self.selection endLiveSelection];
        return iTermClickSideEffectsNone;
    } else if (numTouches == 3 && _mouseDown) {
        // Three finger tap is valid but not emulating middle button
        const BOOL performedAction = [pointer_ mouseUp:event withTouches:numTouches];
        DLog(@"set mouseDown=NO");
        _mouseDown = NO;
        DLog(@"Returning from mouseUp because there were 3 touches. Set mouseDown=NO");
        // We don't want a three finger tap followed by a scrollwheel to make a selection.
        if (self.selection.live) {
            [self copyAfterSelectionEndsIfDesired];
        }
        [self.selection endLiveSelection];
        return performedAction ? iTermClickSideEffectsPerformBoundAction : iTermClickSideEffectsNone;
    }
    dragOk_ = NO;
    _semanticHistoryDragged = NO;
    if ([pointer_ eventEmulatesRightClick:event]) {
        const BOOL performedAction = [pointer_ mouseUp:event withTouches:numTouches];
        DLog(@"Returning from mouseUp because we'e emulating a right click.");
        if (self.selection.live) {
            [self copyAfterSelectionEndsIfDesired];
        }
        [self.selection endLiveSelection];
        return performedAction ? iTermClickSideEffectsPerformBoundAction : iTermClickSideEffectsNone;
    }
    const BOOL cmdActuallyPressed = (([event it_modifierFlags] & NSEventModifierFlagCommand) != 0);
    // Make an exception to the first-mouse rule when cmd-click is set to always invoke
    // semantic history.
    const BOOL cmdPressed = cmdActuallyPressed && (!_mouseDownWasFirstMouse ||
                                                   [iTermAdvancedSettingsModel cmdClickWhenInactiveInvokesSemanticHistory]);
    if (_mouseDown == NO) {
        DLog(@"Returning from mouseUp because the mouse was never down.");
        if (self.selection.live) {
            [self copyAfterSelectionEndsIfDesired];
        }
        [self.selection endLiveSelection];
        return iTermClickSideEffectsIgnore;
    }

    DLog(@"Set mouseDown=NO");
    _mouseDown = NO;
    _mouseDownOnSelection = NO;

    [_selectionScrollHelper mouseUp];
    const BOOL mouseDragged = (_mouseDragged && _committedToDrag);
    _committedToDrag = NO;

    BOOL isUnshiftedSingleClick = ([event clickCount] < 2 &&
                                   !mouseDragged &&
                                   !([event it_modifierFlags] & NSEventModifierFlagShift));
    BOOL isShiftedSingleClick = ([event clickCount] == 1 &&
                                 !mouseDragged &&
                                 ([event it_modifierFlags] & NSEventModifierFlagShift));
    BOOL willFollowLink = (isUnshiftedSingleClick &&
                           cmdPressed &&
                           [iTermPreferences boolForKey:kPreferenceKeyCmdClickOpensURLs]);

    // Reset _mouseDragged; it won't be needed again and we don't want it to get stuck like in
    // issue 3766.
    _mouseDragged = NO;

    [_mouseReportingFrustrationDetector mouseUp:event reported:[self mouseEventIsReportable:event]];
    // Send mouse up event to host if xterm mouse reporting is on
    iTermClickSideEffects result = iTermClickSideEffectsNone;
    if ([self reportMouseEvent:event]) {
        result |= iTermClickSideEffectsReport;
        if (willFollowLink) {
            // This is a special case. Cmd-click is treated like alt-click at the protocol
            // level (because we use alt to disable mouse reporting, unfortunately). Few
            // apps interpret alt-clicks specially, and we really want to handle cmd-click
            // on links even when mouse reporting is on. Link following has to be done on
            // mouse up to allow the user to drag links and to cancel accidental clicks (by
            // doing mouseUp far away from mouseDown). So we report the cmd-click as an
            // alt-click and then open the link. Note that cmd-alt-click isn't handled here
            // because you won't get here if alt is pressed. Note that openTargetWithEvent:
            // may not do anything if the pointer isn't over a clickable string.
            [self.mouseDelegate mouseHandlerOpenTargetWithEvent:event inBackground:NO];
            result |= iTermClickSideEffectsOpenTarget;
        }
        DLog(@"Returning from mouseUp because the mouse event was reported.");
        [self.selection endLiveSelection];
        return result;
    }

    // Unlock auto scrolling as the user as finished selecting text
    if ([self.mouseDelegate mouseHandlerIsScrolledToBottom:self]) {
        [self.mouseDelegate mouseHandlerUnlockScrolling:self];
    }

    if (!cmdActuallyPressed) {
        // Make ourselves the first responder except on cmd-click. A cmd-click on a non-key window
        // gets treated as a click that doesn't raise the window. A cmd-click in an inactive pane
        // in the key window shouldn't make it first responder, but still gets treated as cmd-click.
        //
        // We use cmdActuallyPressed instead of cmdPressed because on first-mouse cmdPressed gets
        // unset so this function generally behaves like it got a plain click (this is the exception).
        [self.mouseDelegate mouseHandlerMakeFirstResponder:self];
    }

    const BOOL wasSelecting = self.selection.live;
    [self.selection endLiveSelection];
    VT100GridCoord findOnPageCursor = {0};
    if (isUnshiftedSingleClick) {
        // Just a click in the window.
        DLog(@"is a click in the window");

        BOOL altPressed = ([event it_modifierFlags] & NSEventModifierFlagOption) != 0;
        if (altPressed &&
            [iTermPreferences boolForKey:kPreferenceKeyOptionClickMovesCursor] &&
            !_mouseDownWasFirstMouse) {
            // This moves the cursor, but not if mouse reporting is on for button clicks.
            // It's also off for first mouse because of issue 2943 (alt-click to activate an app
            // is used to order-back all of the previously active app's windows).
            switch ([self.mouseDelegate mouseHandlerMouseMode:self]) {
                case MOUSE_REPORTING_NORMAL:
                case MOUSE_REPORTING_BUTTON_MOTION:
                case MOUSE_REPORTING_ALL_MOTION:
                    // Reporting mouse clicks. The remote app gets preference.
                    break;

                default: {
                    // Not reporting mouse clicks, so we'll move the cursor since the remote app
                    // can't.
                    VT100GridCoord coord = [self.mouseDelegate mouseHandlerCoordForPointInWindow:[event locationInWindow]];
                    if (!cmdPressed) {
                        [self.mouseDelegate mouseHandlerMoveCursorToCoord:coord
                                                                 forEvent:event];
                        result |= iTermClickSideEffectsMoveCursor;
                    }
                    break;
                }
            }
        }

        VT100GridCoord clickCoord = VT100GridCoordInvalid;

        if (willFollowLink) {
            [self.mouseDelegate mouseHandlerOpenTargetWithEvent:event inBackground:altPressed];
            result |= iTermClickSideEffectsOpenTarget;
        } else {
            clickCoord =
            [self.mouseDelegate mouseHandler:self
                                  clickPoint:event
                               allowOverflow:NO];
            if (clickCoord.x >= 0 && clickCoord.y >= 0) {
                [self.mouseDelegate mouseHandlerSetFindOnPageCursorCoord:clickCoord];
                result |= iTermClickSideEffectsMoveFindOnPageCursor;
            }
        }
        if ([self.mouseDelegate mouseHandlerAtPasswordPrompt:self] &&
            !altPressed &&
            !cmdPressed) {
            if (VT100GridCoordEquals(clickCoord, VT100GridCoordInvalid)) {
                clickCoord =
                [self.mouseDelegate mouseHandler:self
                                      clickPoint:event
                                   allowOverflow:NO];
            }
            const VT100GridCoord cursorCoord =
            [self.mouseDelegate mouseHandlerCursorCoord:self];
            if (VT100GridCoordEquals(clickCoord, cursorCoord)) {
                [self.mouseDelegate mouseHandlerOpenPasswordManager:self];
                result |= iTermClickSideEffectsOpenPasswordManager;
            }
        }
    } else if (isShiftedSingleClick &&
               [self.mouseDelegate mouseHandler:self getFindOnPageCursor:&findOnPageCursor] &&
               ![self.selection hasSelection]) {
        const long long overflow = [_mouseDelegate mouseHandlerTotalScrollbackOverflow:self];
        [self.selection beginSelectionAtAbsCoord:VT100GridAbsCoordFromCoord(findOnPageCursor, overflow)
                                            mode:kiTermSelectionModeCharacter
                                          resume:NO
                                          append:NO];

        const VT100GridCoord newEndPoint =
        [self.mouseDelegate mouseHandler:self clickPoint:event allowOverflow:YES];
        [self.selection moveSelectionEndpointTo:VT100GridAbsCoordFromCoord(newEndPoint, overflow)];
        [self.selection endLiveSelection];

        [self.mouseDelegate mouseHandlerResetFindOnPageCursor:self];
        result |= iTermClickSideEffectsMoveFindOnPageCursor | iTermClickSideEffectsModifySelection;
    }

    DLog(@"Has selection=%@, delegate=%@ wasSelecting=%@", @([self.selection hasSelection]), self.mouseDelegate, @(wasSelecting));
    if ([self.selection hasSelection] &&
        event.clickCount == 1 &&
        !wasSelecting &&
        _lastMouseDownOnSelectedText) {
        // Click on selection. When the mouse-down was on the selection we delay clearing it until
        // mouse-up so you have the chance to drag it.
        [self.selection clearSelection];
        result |= iTermClickSideEffectsModifySelection;
    }
    if (wasSelecting) {
        [self copyAfterSelectionEndsIfDesired];
    }

    DLog(@"Mouse up. selection=%@", self.selection);

    [self.mouseDelegate mouseHandlerDidMutateState:self];
    return result;
}

- (void)copyAfterSelectionEndsIfDesired {
    DLog(@"hasSelection=%@ handlerIsValid=%@ self=%@",
         @([self.selection hasSelection]),
         @([self.mouseDelegate mouseHandlerIsValid:self]),
         self);
    if ([self.selection hasSelection] &&
        [self.mouseDelegate mouseHandlerIsValid:self]) {
        // if we want to copy our selection, do so
        DLog(@"selection copies text=%@", @([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]));
        if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
            [self.mouseDelegate mouseHandlerCopy:self];
        }
    }
}

- (void)mouseDragged:(NSEvent *)event {
    const iTermClickSideEffects sideEffects = [self mouseDraggedImpl:event];
    if (sideEffects != iTermClickSideEffectsIgnore) {
        [self setMouseInfoForEvent:event sideEffects:sideEffects];
    }
}

- (iTermClickSideEffects)mouseDraggedImpl:(NSEvent *)event {
    DLog(@"mouseDragged: %@, numTouches=%d", event, _numTouches);
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    [_threeFingerTapGestureRecognizer mouseDragged];
    const BOOL wasMakingThreeFingerSelection = _makingThreeFingerSelection;
    _makingThreeFingerSelection = (_numTouches == 3);
    DLog(@"_makingThreeFingerSelection <- %@", @(_makingThreeFingerSelection));
    if (_mouseDownIsThreeFingerClick) {
        DLog(@"is three finger click");
        return iTermClickSideEffectsIgnore;
    }
    // Prevent accidental dragging while dragging semantic history item.
    BOOL dragThresholdMet = NO;
    const NSPoint locationInWindow = [event locationInWindow];
    const NSPoint locationInTextView =
    [self.mouseDelegate mouseHandler:self viewCoordForEvent:event clipped:YES];

    const VT100GridCoord clickPointGridCoord =
    [self.mouseDelegate mouseHandler:self clickPoint:event allowOverflow:YES];
    const int x = clickPointGridCoord.x;
    const int y = clickPointGridCoord.y;

    NSPoint mouseDownLocation = [_mouseDownEvent locationInWindow];
    if (EuclideanDistance(mouseDownLocation, locationInWindow) >= kDragThreshold) {
        dragThresholdMet = YES;
        _committedToDrag = YES;
    }
    if ([event eventNumber] == _firstMouseEventNumber) {
        // We accept first mouse for the purposes of focusing or dragging a
        // split pane but not for making a selection.
        return iTermClickSideEffectsIgnore;
    }
    if (!dragOk_ && !_makingThreeFingerSelection) {
        DLog(@"drag not ok");
        return iTermClickSideEffectsIgnore;
    }

    [_mouseReportingFrustrationDetector mouseDragged:event reported:[self mouseEventIsReportable:event]];
    if ([self reportMouseEvent:event]) {
        DLog(@"Reported drag");
        _committedToDrag = YES;
        return iTermClickSideEffectsReport;
    }
    DLog(@"Did not report drag");
    [self.mouseDelegate mouseHandlerWillDrag:self];

    const BOOL pressingCmdOnly = ([event it_modifierFlags] & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) == NSEventModifierFlagCommand;
    if (!pressingCmdOnly || dragThresholdMet) {
        DLog(@"mousedragged = yes");
        _mouseDragged = YES;
    }


    // It's ok to drag if Cmd is not required to be pressed or Cmd is pressed.
    const BOOL okToDrag = (![iTermAdvancedSettingsModel requireCmdForDraggingText] ||
                           ([event it_modifierFlags] & NSEventModifierFlagCommand));
    if (okToDrag) {
        if (_mouseDownOnImage && dragThresholdMet) {
            _committedToDrag = YES;
            [self.mouseDelegate mouseHandler:self
                                   dragImage:_imageBeingClickedOn
                                    forEvent:event];
            return iTermClickSideEffectsDrag;
        } else if (_mouseDownOnSelection == YES && dragThresholdMet) {
            DLog(@"drag and drop a selection");
            // Drag and drop a selection
            NSString *theSelectedText = [self.mouseDelegate mouseHandlerSelectedText:self];
            if ([theSelectedText length] > 0) {
                _committedToDrag = YES;
                [self.mouseDelegate mouseHandler:self dragText:theSelectedText forEvent:event];
                DLog(@"Mouse drag. selection=%@", self.selection);
                return iTermClickSideEffectsDrag;
            }
        }
    }

    if (pressingCmdOnly && !dragThresholdMet) {
        // If you're holding cmd (but not opt) then you're either trying to click on a link and
        // accidentally dragged a little bit, or you're trying to drag a selection. Do nothing until
        // the threshold is met.
        DLog(@"drag during cmd click");
        return iTermClickSideEffectsIgnore;
    }
    if (_mouseDownOnSelection == YES &&
        ([event it_modifierFlags] & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) == (NSEventModifierFlagOption | NSEventModifierFlagCommand) &&
        !dragThresholdMet) {
        // Would be a drag of a rect region but mouse hasn't moved far enough yet. Prevent the
        // selection from changing.
        DLog(@"too-short drag of rect region");
        return iTermClickSideEffectsIgnore;
    }

    if (![self.selection hasSelection] &&
        pressingCmdOnly &&
        _semanticHistoryDragged == NO) {
        // Only one Semantic History check per drag
        _semanticHistoryDragged = YES;
        [self.mouseDelegate mouseHandler:self
            dragSemanticHistoryWithEvent:event
                                   coord:VT100GridCoordMake(x, y)];
        return iTermClickSideEffectsDrag;
    }

    [_selectionScrollHelper mouseDraggedTo:locationInTextView coord:VT100GridCoordMake(x, y)];

    if (!wasMakingThreeFingerSelection &&
        _makingThreeFingerSelection) {
        DLog(@"Just started a three finger selection in mouseDragged (because of macOS bugs)");
        const BOOL shiftPressed = ([event it_modifierFlags] & NSEventModifierFlagShift) != 0;
        const BOOL isExtension = ([self.selection hasSelection] && shiftPressed);
        const BOOL altPressed = ([event it_modifierFlags] & NSEventModifierFlagOption) != 0;
        const BOOL cmdPressed = ([event it_modifierFlags] & NSEventModifierFlagCommand) != 0;
        const long long overflow = [_mouseDelegate mouseHandlerTotalScrollbackOverflow:self];
        if (isExtension &&
            [self.selection hasSelection]) {
            if (!self.selection.live) {
                DLog(@"Begin extending");
                [self.selection beginExtendingSelectionAt:VT100GridAbsCoordMake(x, y + overflow)];
            }
        } else {
            iTermSelectionMode mode;
            if ((event.it_modifierFlags & kRectangularSelectionModifierMask) == kRectangularSelectionModifiers) {
                mode = kiTermSelectionModeBox;
            } else {
                mode = kiTermSelectionModeCharacter;
            }

            DLog(@"Begin selection");
            [self.selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(x, y + overflow)
                                                mode:mode
                                              resume:NO
                                              append:(cmdPressed && !altPressed)];
            self.selection.resumable = YES;
        }
    } else {
        DLog(@"Update live selection during drag");
        if ([self.mouseDelegate mouseHandler:self moveSelectionToGridCoord:VT100GridCoordMake(x, y)
                                   viewCoord:locationInTextView]) {
            _committedToDrag = YES;
        }
    }

    return iTermClickSideEffectsModifySelection;
}

#pragma mark - Right mouse

- (void)rightMouseDown:(NSEvent *)event superCaller:(void (^)(void))superCaller {
    if ([iTermPreferences boolForKey:kPreferenceKeyFocusOnRightOrMiddleClick]) {
        [_mouseDelegate mouseHandlerMakeKeyAndOrderFrontAndMakeFirstResponderAndActivateApp:self];
    }
    [_mouseReportingFrustrationDetector otherMouseEvent];
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    if ([_threeFingerTapGestureRecognizer rightMouseDown:event]) {
        DLog(@"Cancel right mouse down");
        return;
    }
    if ([pointer_ mouseDown:event
                withTouches:_numTouches
               ignoreOption:[self terminalWantsMouseReports]]) {
        [self setMouseInfoForEvent:event
                       sideEffects:iTermClickSideEffectsPerformBoundAction];
        return;
    }
    if ([self reportMouseEvent:event]) {
        [self setMouseInfoForEvent:event
                       sideEffects:iTermClickSideEffectsReport];
        return;
    }

    superCaller();
    [self setMouseInfoForEvent:event
                   sideEffects:iTermClickSideEffectsNone];
}

- (void)rightMouseUp:(NSEvent *)event superCaller:(void (^)(void))superCaller {
    [_mouseReportingFrustrationDetector otherMouseEvent];
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    if ([_threeFingerTapGestureRecognizer rightMouseUp:event]) {
        return;
    }

    if ([pointer_ mouseUp:event withTouches:_numTouches]) {
        [self setMouseInfoForEvent:event
                       sideEffects:iTermClickSideEffectsPerformBoundAction];
        return;
    }
    if ([self reportMouseEvent:event]) {
        [self setMouseInfoForEvent:event
                       sideEffects:iTermClickSideEffectsReport];
        return;
    }
    superCaller();
    [self setMouseInfoForEvent:event
                   sideEffects:iTermClickSideEffectsNone];
}

- (void)rightMouseDragged:(NSEvent *)event superCaller:(void (^)(void))superCaller {
    [_mouseReportingFrustrationDetector otherMouseEvent];
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    [_threeFingerTapGestureRecognizer mouseDragged];
    if ([self reportMouseEvent:event]) {
        [self setMouseInfoForEvent:event sideEffects:iTermClickSideEffectsReport];
        return;
    }
    superCaller();
    [self setMouseInfoForEvent:event sideEffects:iTermClickSideEffectsNone];
}


#pragma mark - Other mouse

- (void)otherMouseUp:(NSEvent *)event superCaller:(void (^)(void))superCaller {
    [_mouseReportingFrustrationDetector otherMouseEvent];
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    if ([self reportMouseEvent:event]) {
        [self setMouseInfoForEvent:event
                       sideEffects:iTermClickSideEffectsReport];
        return;
    }

    iTermClickSideEffects sideEffects = iTermClickSideEffectsNone;
    if (!_mouseDownIsThreeFingerClick) {
        DLog(@"Sending third button press up to super");
        superCaller();
    }
    DLog(@"Sending third button press up to pointer controller");
    if ([pointer_ mouseUp:event withTouches:_numTouches]) {
        sideEffects |= iTermClickSideEffectsPerformBoundAction;
    }
    [self setMouseInfoForEvent:event
                   sideEffects:sideEffects];
}

// TODO: disable other, right mouse for inactive panes
- (void)otherMouseDown:(NSEvent *)event {
    if ([iTermPreferences boolForKey:kPreferenceKeyFocusOnRightOrMiddleClick]) {
        [_mouseDelegate mouseHandlerMakeKeyAndOrderFrontAndMakeFirstResponderAndActivateApp:self];
    }
    [_mouseReportingFrustrationDetector otherMouseEvent];
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    iTermClickSideEffects sideEffects = iTermClickSideEffectsNone;
    if ([self reportMouseEvent:event]) {
        sideEffects |= iTermClickSideEffectsReport;
    }

    const BOOL performed = [pointer_ mouseDown:event
                                   withTouches:_numTouches
                                  ignoreOption:[self terminalWantsMouseReports]];
    if (performed) {
        sideEffects |= iTermClickSideEffectsPerformBoundAction;
    }
    [self setMouseInfoForEvent:event
                   sideEffects:sideEffects];
}

- (void)otherMouseDragged:(NSEvent *)event superCaller:(void (^)(void))superCaller {
    [_mouseReportingFrustrationDetector otherMouseEvent];
    [_altScreenMouseScrollInferrer nonScrollWheelEvent:event];
    [_threeFingerTapGestureRecognizer mouseDragged];
    if ([self reportMouseEvent:event]) {
        [self setMouseInfoForEvent:event sideEffects:iTermClickSideEffectsReport];
        return;
    }
    superCaller();
    [self setMouseInfoForEvent:event sideEffects:iTermClickSideEffectsNone];
}

#pragma mark - Responder

- (void)didResignFirstResponder {
    DLog(@"set scrolling=NO for %@\n%@", self, [NSThread callStackSymbols]);
    _scrolling = NO;
    [_altScreenMouseScrollInferrer firstResponderDidChange];
}

- (void)didBecomeFirstResponder {
    DLog(@"set scrolling=NO for %@\n%@", self, [NSThread callStackSymbols]);
    _scrolling = NO;
    [_altScreenMouseScrollInferrer firstResponderDidChange];
}

#pragma mark - Misc mouse

- (BOOL)scrollWheel:(NSEvent *)event pointInView:(NSPoint)point {
    if (event.momentumPhase == NSEventPhaseBegan) {
        DLog(@"set scrolling=YES for %@\n%@", self, [NSThread callStackSymbols]);
        _scrolling = YES;
    } else if (event.momentumPhase == NSEventPhaseEnded ||
               event.momentumPhase == NSEventPhaseCancelled ||
               event.momentumPhase == NSEventPhaseStationary) {
        DLog(@"set scrolling=NO for %@\n%@", self, [NSThread callStackSymbols]);
        _scrolling = NO;
    }
    [_threeFingerTapGestureRecognizer scrollWheel];

    if (!_haveSeenScrollWheelEvent) {
        // Work around a weird bug. Commit 9e4b97b18fac24bea6147c296b65687f0523ad83 caused it.
        // When you restore a window and have an inline scroller (but not a legacy scroller!) then
        // it will be at the top, even though we're scrolled to the bottom. You can either jiggle
        // it after a delay to fix it, or after thousands of dispatch_async calls, or here. None of
        // these make any sense, nor does the bug itself. I get the feeling that a giant rats' nest
        // of insanity underlies scroll wheels on macOS.
        _haveSeenScrollWheelEvent = YES;
        [self.mouseDelegate mouseHandlerJiggle:self];
    }
    if (event.momentumPhase == NSEventPhaseNone ||
        event.momentumPhase == NSEventPhaseBegan) {
        DLog(@"disableScrollReportingUntilMomentumEnds <- NO");
        _disableScrollReportingUntilMomentumEnds = NO;
    }
    if ([self scrollWheelShouldSendDataForEvent:event at:point]) {
        DLog(@"disableScrollReportingUntilMomentumEnds=%@", @(_disableScrollReportingUntilMomentumEnds));
        if (!_disableScrollReportingUntilMomentumEnds) {
            [self sendDataForScrollEvent:event];
            return NO;
        }
    } else if (event.momentumPhase == NSEventPhaseBegan) {
        DLog(@"disableScrollReportingUntilMomentumEnds <- YES");
        _disableScrollReportingUntilMomentumEnds = YES;
    }
    if (event.momentumPhase == NSEventPhaseEnded) {
        DLog(@"disableScrollReportingUntilMomentumEnds <- NO");
        _disableScrollReportingUntilMomentumEnds = NO;
    }
    BOOL reportable = NO;
    if ([self handleMouseEvent:event testOnly:NO deltaOut:NULL reportableOut:&reportable]) {
        DLog(@"Mouse event was handled so returning");
        return NO;
    }
    if (self.selection.live) {
        DLog(@"In live selection");
        // Scroll via wheel while selecting. This is even possible with the trackpad by using
        // three fingers as described in issue 8538.
        if ([self.mouseDelegate mouseHandler:self moveSelectionToPointInEvent:event]) {
            _committedToDrag = YES ;
        }
        return YES;
    }
    // Swipe between tabs.
    if ([self tryToHandleSwipeBetweenTabsForScrollWheelEvent:event]) {
        DLog(@"Handled as swipe between tabs");
        return YES;
    }
    return YES;
}

- (void)sendDataForScrollEvent:(NSEvent *)event {
    DLog(@"Scroll wheel sending data");
    const CGFloat delta = [self.mouseDelegate mouseHandler:self accumulateScrollFromEvent:event];
    BOOL forceLatin1 = NO;
    NSString *stringToSend = [self.mouseDelegate mouseHandler:self
                                           stringForUpOrRight:delta >= 0
                                                     vertical:event.it_isVerticalScroll
                                                        flags:event.it_modifierFlags
                                                       latin1:&forceLatin1];

    if (stringToSend) {
        for (int i = 0; i < ceil(fabs(delta)); i++) {
            [self.mouseDelegate mouseHandler:self
                                  sendString:stringToSend
                                      latin1:forceLatin1];
        }
        [self.mouseDelegate mouseHandlerRemoveSelection:self];
    }
}

// See issue 1350
- (BOOL)tryToHandleSwipeBetweenTabsForScrollWheelEvent:(NSEvent *)event {
    return [_swipeTracker handleEvent:event];
}

- (void)swipeWithEvent:(NSEvent *)event {
    [pointer_ swipeWithEvent:event];
}

// If this changes also update wantsMouseMovementEvents
- (void)mouseMoved:(NSEvent *)event {
    [self reportMouseEvent:event];
}

- (void)pressureChangeWithEvent:(NSEvent *)event {
    [pointer_ pressureChangeWithEvent:event];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent {
    _firstMouseEventNumber = [theEvent eventNumber];
    DLog(@"Set firstMouseEventNumber to %@", @(_firstMouseEventNumber));
    return YES;
}

#pragma mark - Other APIs

- (void)performBlockWithThreeTouches:(void (^)(void))block {
    int saved = _numTouches;
    _numTouches = 3;
    block();
    DLog(@"Restore numTouches to saved value of %d", saved);
    _numTouches = saved;
}

- (BOOL)threeFingerTap:(NSEvent *)ev {
    return [pointer_ threeFingerTap:ev];
}

- (void)keyDown:(NSEvent *)event {
    [_mouseReportingFrustrationDetector keyDown:event];
    [_altScreenMouseScrollInferrer keyDown:event];
}

- (void)selectionScrollWillStart {
    _committedToDrag = YES;
}

- (void)didDragSemanticHistory {
    _committedToDrag = YES;

    // Valid drag, so we reset the flag because mouseUp doesn't get called when a drag is done
    _semanticHistoryDragged = NO;
}

- (void)didCopyToPasteboardWithControlSequence {
    [_mouseReportingFrustrationDetector didCopyToPasteboardWithControlSequence];
}

- (BOOL)wantsScrollWheelMomentumEvents {
    return _scrolling;
}

#pragma mark - Private

// Emulates a third mouse button event (up or down, based on 'isDown').
// Requires a real mouse event 'event' to build off of. This has the side
// effect of setting mouseDownIsThreeFingerClick_, which (when set) indicates
// that the current mouse-down state is "special" and disables certain actions
// such as dragging.
// The NSEvent method for creating an event can't be used because it doesn't let you set the
// buttonNumber field.
- (void)emulateThirdButtonPressDown:(BOOL)isDown withEvent:(NSEvent *)event {
    if (isDown) {
        _mouseDownIsThreeFingerClick = isDown;
        DLog(@"emulateThirdButtonPressDown - set mouseDownIsThreeFingerClick=YES");
    }

    NSEvent *fakeEvent = [event eventWithButtonNumber:2];

    int saved = _numTouches;
    _numTouches = 1;
    if (isDown) {
        DLog(@"Emulate third button press down");
        [self otherMouseDown:fakeEvent];
    } else {
        DLog(@"Emulate third button press up");
        [self.mouseDelegate mouseHandler:self sendFakeOtherMouseUp:fakeEvent];
    }
    _numTouches = saved;
    if (!isDown) {
        _mouseDownIsThreeFingerClick = isDown;
        DLog(@"emulateThirdButtonPressDown - set mouseDownIsThreeFingerClick=NO");
    }
}

- (iTermSelection *)selection {
    return [self.mouseDelegate mouseHandlerCurrentSelection:self];
}

#pragma mark Reporting

- (BOOL)reportMouseDrags {
    switch ([self.mouseDelegate mouseHandlerMouseMode:self]) {
        case MOUSE_REPORTING_NORMAL:
        case MOUSE_REPORTING_BUTTON_MOTION:
        case MOUSE_REPORTING_ALL_MOTION:
            return YES;

        case MOUSE_REPORTING_NONE:
        case MOUSE_REPORTING_HIGHLIGHT:
            break;
    }
    return NO;
}

// Returns YES if the mouse event would be handled, ignoring trivialities like a drag that hasn't
// changed coordinate since the last drag.
- (BOOL)mouseEventIsReportable:(NSEvent *)event {
    return [self handleMouseEvent:event testOnly:YES deltaOut:NULL reportableOut:NULL];
}

// Returns YES if the mouse event should not be handled natively.
// If thiss changes also update wantsMouseMovementEvents
- (BOOL)reportMouseEvent:(NSEvent *)event {
    return [self handleMouseEvent:event testOnly:NO deltaOut:NULL reportableOut:NULL];
}

// When in doubt this can return YES at the cost of a little CPU when moving the mouse around.
- (BOOL)wantsMouseMovementEvents {
    if (![self.mouseDelegate mouseHandlerAnyReportingModeEnabled:self]) {
        DLog(@"Mouse reporting disabled so do NOT track mouse moves");
        return NO;
    }
    DLog(@"Mouse reporting enabled so track mouse moves");
    return YES;
}

// If this changes also update wantsMouseMovementEvents
- (BOOL)handleMouseEvent:(NSEvent *)event
                testOnly:(BOOL)testOnly
                deltaOut:(CGSize *)deltaOut
           reportableOut:(BOOL *)reportableOut {
    DLog(@"handleMouseEvent:%@ testOnly:%@", event, @(testOnly));
    if (![self.mouseDelegate mouseHandlerAnyReportingModeEnabled:self]) {
        // Fast path to avoid burning CPU when mouse reporting is off.
        DLog(@"Fast path: not reportable");
        if (reportableOut) {
            *reportableOut = NO;
        }
        return NO;
    }
    const NSPoint point =
    [self.mouseDelegate mouseHandler:self viewCoordForEvent:event clipped:NO];
    DLog(@"point=%@", NSStringFromPoint(point));

    if (![self shouldReportMouseEvent:event at:point]) {
        DLog(@"Not reportable");
        if (reportableOut) {
            *reportableOut = NO;
        }
        return NO;
    }
    if (reportableOut) {
        DLog(@"Is reportable");
        *reportableOut = YES;
    }

    VT100GridCoord coord = [self.mouseDelegate mouseHandlerCoordForPointInView:point];
    const CGSize delta = [self.mouseDelegate mouseHandlerAccumulatedDelta:self forEvent:event];
    DLog(@"delta=%@", NSStringFromSize(delta));
    if (deltaOut) {
        *deltaOut = delta;
    }

    return [self.mouseDelegate mouseHandler:self
                           reportMouseEvent:event.type
                                  modifiers:event.it_modifierFlags
                                     button:[self mouseReportingButtonNumberForEvent:event]
                                 coordinate:coord
                                      point:[self.mouseDelegate mouseHandlerReportablePointForPointInView:point]
                                      event:event
                                      delta:delta
                   allowDragBeforeMouseDown:_makingThreeFingerSelection
                                   testOnly:testOnly];
}

// If mouse reports are sent to the delegate, will it use them? Use with -xtermMouseReporting, which
// understands Option to turn off reporting.
- (BOOL)terminalWantsMouseReports {
    const MouseMode mouseMode = [self.mouseDelegate mouseHandlerMouseMode:self];
    return ([self.mouseDelegate mouseHandlerReportingAllowed:self] &&
            mouseMode != MOUSE_REPORTING_NONE &&
            mouseMode != MOUSE_REPORTING_HIGHLIGHT);
}

- (BOOL)shouldReportMouseEvent:(NSEvent *)event at:(NSPoint)point {
    if (![self.mouseDelegate mouseHandlerCanWriteToTTY:self]) {
        DLog(@"TTY is not writable");
        return NO;
    }
    if (![self.mouseDelegate mouseHandler:self viewCoordIsReportable:point]) {
        DLog(@"Coord not reportable");
        return NO;
    }
    if (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp) {
        if (_mouseDownWasFirstMouse && ![iTermAdvancedSettingsModel alwaysAcceptFirstMouse]) {
            DLog(@"First mouse is not reportable");
            return NO;
        }
        // Three-finger click mousedown should not be reported normally to avoid accidental
        // reports because what reporting a 3-finger click when not emulating the middle
        // button is nonsense. It's certainly not something mouse reporting supports.
        // These are buttonNumber=0, _numTouches=3. Issue 8481.
        //
        // However, three-finger mousedown with *three-finger drag enabled* must be reported so
        // 3-finger drags get reported.
        //
        // Three-finger tap emulating middle click has button 2. Middle clicks are reportable.
        //
        // A 2-finger mouse-down is reportable because it's necessary for drag reporting to work
        // with two touches. Issue 8481.
        if (event.buttonNumber == 0 && _numTouches == 3 && ![self trackpadThreeFingerDragEnabled]) {
            DLog(@"Three touches on left button up/down, but three-finger drag is disabled, so don't report it.");
            return NO;
        }
    }
    if ((event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp) &&
        ![self.mouseDelegate mouseHandlerViewIsFirstResponder:self]) {
        DLog(@"Not first responder");
        return NO;
    }
    if (![self.mouseDelegate mouseHandlerShouldReportClicksAndDrags:self]) {
        if (event.type == NSEventTypeLeftMouseDown ||
            event.type == NSEventTypeLeftMouseUp ||
            event.type == NSEventTypeLeftMouseDragged ||
            event.type == NSEventTypeRightMouseDown ||
            event.type == NSEventTypeRightMouseUp ||
            event.type == NSEventTypeRightMouseDragged ||
            event.type == NSEventTypeOtherMouseDown ||
            event.type == NSEventTypeOtherMouseUp ||
            event.type == NSEventTypeOtherMouseDragged) {
            DLog(@"Don't report clicks and drags");
            return NO;
        }
    }
    if (![self mouseReportingAllowedForEvent:event]) {
        DLog(@"Mouse reporting disallowed");
        return NO;
    }
    if (event.type == NSEventTypeScrollWheel) {
        return [self.mouseDelegate mouseHandlerShouldReportScroll:self];
    }
    return [self.mouseDelegate mouseHandlerViewHasFocus:self];
}

- (BOOL)mouseReportingAllowedForEvent:(NSEvent *)event {
    if (![self.mouseDelegate mouseHandlerReportingAllowed:self]) {
        DLog(@"Delegate says mouse reporting not allowed");
        return NO;
    }
    if (event.it_modifierFlags & NSEventModifierFlagOption) {
        DLog(@"Not reporting mouse event because you pressed option");
        return NO;
    }
    return YES;
}

- (MouseButtonNumber)mouseReportingButtonNumberForEvent:(NSEvent *)event {
    DLog(@"Button number %@ %@", @(event.buttonNumber), @(event.type));
    if (event.type == NSEventTypeScrollWheel) {
        DLog(@"X: %@ Y: %@", @(event.scrollingDeltaX), @(event.scrollingDeltaY));
    }
    switch (event.type) {
        case NSEventTypeLeftMouseDragged:
        case NSEventTypeLeftMouseDown:
        case NSEventTypeLeftMouseUp:
            return MOUSE_BUTTON_LEFT;

        case NSEventTypeRightMouseDown:
        case NSEventTypeRightMouseUp:
        case NSEventTypeRightMouseDragged:
            return MOUSE_BUTTON_RIGHT;

        case NSEventTypeOtherMouseDown:
        case NSEventTypeOtherMouseUp:
        case NSEventTypeOtherMouseDragged:
            switch (event.buttonNumber) {
                case 2:
                    return MOUSE_BUTTON_MIDDLE;
                case 3:
                    return MOUSE_BUTTON_BACKWARD;
                case 4:
                    return MOUSE_BUTTON_FORWARD;
                case 5:
                    return MOUSE_BUTTON_10;
                case 6:
                    return MOUSE_BUTTON_11;
                default:
                    return MOUSE_BUTTON_UNKNOWN;
            }


        case NSEventTypeScrollWheel:
            if (fabs(event.scrollingDeltaX) > fabs(event.scrollingDeltaY)) {
                BOOL scrollLeft = [event scrollingDeltaX] > 0;
                if (![iTermAdvancedSettingsModel naturalScrollingAffectsHorizontalMouseReporting]) {
                    // macOS reverses direction for horizontal scrolls when natural mouse reporting
                    // is on. This is what the user wants if it moves the window contents but in
                    // a terminal it will often send arrow keys and that is total chaos. Issue 10881
                    const BOOL natural = [[[NSUserDefaults standardUserDefaults] objectForKey:@"com.apple.swipescrolldirection"] boolValue];
                    if (natural) {
                        DLog(@"Natural mouse reporting is on so swap left/right scroll wheel button");
                        scrollLeft = !scrollLeft;
                    }
                }
                if (scrollLeft) {
                    return MOUSE_BUTTON_SCROLLLEFT;
                } else {
                    return MOUSE_BUTTON_SCROLLRIGHT;
                }
            } else {
                if ([event scrollingDeltaY] > 0) {
                    return MOUSE_BUTTON_SCROLLDOWN;
                } else {
                    return MOUSE_BUTTON_SCROLLUP;
                }
            }

        default:
            return MOUSE_BUTTON_NONE;
    }
}

- (BOOL)scrollWheelShouldSendDataForEvent:(NSEvent *)event at:(NSPoint)point {
    if (![self.mouseDelegate mouseHandler:self viewCoordIsReportable:point]) {
        DLog(@"Coord not reportable");
        return NO;
    }
    if (event.type != NSEventTypeScrollWheel) {
        DLog(@"Not a wheel event");
        return NO;
    }
    if (![self.mouseDelegate mouseHandlerShowingAlternateScreen:self]) {
        DLog(@"Not in alt screen");
        return NO;
    }
    if (![self.mouseDelegate mouseHandlerCanWriteToTTY:self]) {
        DLog(@"TTY is not writable");
        return NO;
    }
    if ([self shouldReportMouseEvent:event at:point] &&
        [self.mouseDelegate mouseHandlerMouseMode:self] != MOUSE_REPORTING_NONE) {
        // Prefer to report the scroll than to send arrow keys in this mouse reporting mode.
        DLog(@"Mouse reporting is on");
        return NO;
    }
    if (event.it_modifierFlags & NSEventModifierFlagOption) {
        // Hold alt to disable sending arrow keys.
        DLog(@"Alt held");
        return NO;
    }
    const BOOL alternateMouseScroll = [self.mouseDelegate mouseHandlerAlternateScrollModeIsEnabled:self];
    NSString *upString = [iTermAdvancedSettingsModel alternateMouseScrollStringForUp];
    NSString *downString = [iTermAdvancedSettingsModel alternateMouseScrollStringForDown];

    if (event.it_isVerticalScroll && !alternateMouseScroll) {
        DLog(@"Horizontal scroll without alternateMouseScroll enabled, return NO");
        return NO;
    }

    if (alternateMouseScroll || upString.length || downString.length) {
        DLog(@"Feature enabled, have strings.");
        return YES;
    } else {
        DLog(@"Feature disabled or empty/nil string");
        [_altScreenMouseScrollInferrer scrollWheel:event];
        return NO;
    }
}

- (void)setMouseInfoForEvent:(NSEvent *)event
                 sideEffects:(iTermClickSideEffects)sideEffects {
    const NSPoint point =
    [self.mouseDelegate mouseHandler:self viewCoordForEvent:event clipped:NO];
    const VT100GridCoord coord = [self.mouseDelegate mouseHandlerCoordForPointInView:point];
    iTermMouseState state;
    switch (event.type) {
        case NSEventTypeLeftMouseUp:
        case NSEventTypeRightMouseUp:
        case NSEventTypeOtherMouseUp:
            state = iTermMouseStateUp;
            break;

        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown:
            state = iTermMouseStateDown;
            break;

        case NSEventTypeLeftMouseDragged:
        case NSEventTypeRightMouseDragged:
        case NSEventTypeOtherMouseDragged:
            state = iTermMouseStateDrag;
            break;

        default:
            return;
    }
    [self.mouseDelegate mouseHandlerSetClickCoord:coord
                                           button:event.buttonNumber
                                            count:event.clickCount
                                        modifiers:event.it_modifierFlags
                                      sideEffects:sideEffects
                                            state:state];
}


#pragma mark - Selection

- (BOOL)shouldSelectWordWithClicks:(int)clickCount {
    if ([iTermPreferences boolForKey:kPreferenceKeyDoubleClickPerformsSmartSelection]) {
        return clickCount == 4;
    } else {
        return clickCount == 2;
    }
}

- (BOOL)shouldSmartSelectWithClicks:(int)clickCount {
    if ([iTermPreferences boolForKey:kPreferenceKeyDoubleClickPerformsSmartSelection]) {
        return clickCount == 2;
    } else {
        return clickCount == 4;
    }
}

- (BOOL)trackpadThreeFingerDragEnabled {
    static NSUserDefaults *ud;
    if (!ud) {
        ud = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.driver.AppleBluetoothMultitouch.trackpad"];
    }
    return [ud boolForKey:@"TrackpadThreeFingerDrag"];
}

#pragma mark - iTermAltScreenMouseScrollInferrerDelegate

- (void)altScreenMouseScrollInferrerDidInferScrollingIntent:(BOOL)isTrying {
    [self.mouseDelegate mouseHandlerDidInferScrollingIntent:self trying:isTrying];
}

#pragma mark - iTermSwipeTrackerDelegate

- (iTermSwipeState *)swipeTrackerWillBeginNewSwipe:(iTermSwipeTracker *)tracker {
    id<iTermSwipeHandler> handler = [self.mouseDelegate mouseHandlerSwipeHandler:self];
    return [[iTermSwipeState alloc] initWithSwipeHandler:handler];
}

- (BOOL)swipeTrackerShouldBeginNewSwipe:(iTermSwipeTracker *)tracker {
    id<iTermSwipeHandler> handler = [self.mouseDelegate mouseHandlerSwipeHandler:self];
    return [handler swipeHandlerShouldBeginNewSwipe];
}

@end
