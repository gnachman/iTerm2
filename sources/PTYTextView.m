#import "PTYTextView.h"
#import "PTYTextView+MouseHandler.h"

#import "charmaps.h"
#import "FileTransferManager.h"
#import "FontSizeEstimator.h"
#import "FutureMethods.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermBadgeLabel.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermCPS.h"
#import "iTermFindCursorView.h"
#import "iTermFindOnPageHelper.h"
#import "iTermFindPasteboard.h"
#import "iTermImageInfo.h"
#import "iTermKeyboardHandler.h"
#import "iTermLaunchServices.h"
#import "iTermMalloc.h"
#import "iTermMetalClipView.h"
#import "iTermMetalDisabling.h"
#import "iTermMouseCursor.h"
#import "iTermPreferences.h"
#import "iTermPrintAccessoryViewController.h"
#import "iTermQuickLookController.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermScrollAccumulator.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermSelection.h"
#import "iTermSelectionScrollHelper.h"
#import "iTermSetFindStringNotification.h"
#import "iTermShellHistoryController.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextExtractor.h"
#import "iTermTextViewAccessibilityHelper.h"
#import "iTermURLActionHelper.h"
#import "iTermURLStore.h"
#import "iTermVirtualOffset.h"
#import "iTermWebViewWrapperViewController.h"
#import "iTermWarning.h"
#import "MovePaneController.h"
#import "MovingAverage.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSCharacterSet+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSPasteboard+iTerm.h"
#import "NSResponder+iTerm.h"
#import "NSSavePanel+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "NSWindow+PSM.h"
#import "PasteboardHistory.h"
#import "PointerController.h"
#import "PointerPrefsController.h"
#import "PreferencePanel.h"
#import "PTYMouseHandler.h"
#import "PTYNoteView.h"
#import "PTYNoteViewController.h"
#import "PTYScrollView.h"
#import "PTYTab.h"
#import "PTYTask.h"
#import "PTYTextView+ARC.h"
#import "PTYTextView+Private.h"
#import "PTYWindow.h"
#import "RegexKitLite.h"
#import "SCPPath.h"
#import "SearchResult.h"
#import "SmartMatch.h"
#import "SmartSelectionController.h"
#import "SolidColorView.h"
#import "ThreeFingerTapGestureRecognizer.h"
#import "ToastWindowController.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#import "WindowControllerInterface.h"

#import <CoreServices/CoreServices.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <math.h>
#include <sys/time.h>

#import <WebKit/WebKit.h>

NSTimeInterval PTYTextViewHighlightLineAnimationDuration = 0.75;

NSNotificationName iTermPortholesDidChange = @"iTermPortholesDidChange";
NSNotificationName PTYTextViewWillChangeFontNotification = @"PTYTextViewWillChangeFontNotification";
const CGFloat PTYTextViewMarginClickGraceWidth = 2.0;

@interface iTermHighlightRowView: NSView<iTermMetalDisabling>
@end

@implementation iTermHighlightRowView
- (BOOL)viewDisablesMetal {
    return YES;
}
@end

@implementation iTermHighlightedRow

- (instancetype)initWithAbsoluteLineNumber:(long long)row success:(BOOL)success {
    self = [super init];
    if (self) {
        _absoluteLineNumber = row;
        _creationDate = [NSDate timeIntervalSinceReferenceDate];
        _success = success;
    }
    return self;
}

@end

@interface PTYTextView(PointerDelegate)<PointerControllerDelegate>
@end

@implementation PTYTextView {
    // -refresh does not want to be reentrant.
    BOOL _inRefresh;

    // geometry
    double _lineHeight;
    double _charWidth;

    // NSTextInputClient support

    NSDictionary *_markedTextAttributes;

    // blinking cursor
    NSTimeInterval _timeOfLastBlink;

    // Helps with "selection scroll"
    iTermSelectionScrollHelper *_selectionScrollHelper;

    // Helps drawing text and background.
    iTermTextDrawingHelper *_drawingHelper;

    // Last position that accessibility was read up to.
    int _lastAccessibilityCursorX;
    int _lastAccessibiltyAbsoluteCursorY;

    // Detects three finger taps (as opposed to clicks).
    ThreeFingerTapGestureRecognizer *threeFingerTapGestureRecognizer_;

    // Position of cursor last time we looked. Since the cursor might move around a lot between
    // calls to -updateDirtyRects without making any changes, we only redraw the old and new cursor
    // positions.
    VT100GridAbsCoord _previousCursorCoord;

    iTermSelection *_oldSelection;

    // Size of the documentVisibleRect when the badge was set.
    NSSize _badgeDocumentVisibleRectSize;

    // Show a background indicator when in broadcast input mode
    BOOL _showStripesWhenBroadcastingInput;

    iTermTextViewAccessibilityHelper *_accessibilityHelper;
    iTermBadgeLabel *_badgeLabel;

    NSMutableArray<iTermHighlightedRow *> *_highlightedRows;

    // Used to report scroll wheel mouse events.
    iTermScrollAccumulator *_scrollAccumulator;

    iTermRateLimitedUpdate *_shadowRateLimit;
    NSMutableArray<PTYNoteViewController *> *_notes;
    iTermScrollAccumulator *_horizontalScrollAccumulator;
    BOOL _cursorVisible;
    BOOL _haveVisibleBlock;

    NSTimer *_selectCommandTimer;

    iTermTerminalCopyButton *_hoverBlockCopyButton NS_AVAILABLE_MAC(11);
    iTermTerminalFoldBlockButton *_hoverBlockFoldButton NS_AVAILABLE_MAC(11);
    NSMutableArray<iTermTerminalButton *> *_buttons NS_AVAILABLE_MAC(11);

    NSRect _previousCursorFrame;
    BOOL _ignoreMomentumScroll;
    BOOL _haveTooltips;

    NSMutableData *_marginColorWidthBuffer;
    NSMutableData *_marginColorTwiceHeightBuffer;
}


// This is an attempt to fix performance problems that appeared in macOS 10.14
// (rdar://45295749, also mentioned in PTYScrollView.m).
//
// It seems that some combination of implementing drawRect:, not having a
// layer, having a frame larger than the clip view, and maybe some other stuff
// I can't figure out causes terrible performance problems.
//
// For a while I worked around this by dismembering the scroll view. The scroll
// view itself would be hidden, while its scrollers were reparented and allowed
// to remain visible. This worked around it, but I'm sure it caused crashes and
// weird behavior. It may have been responsible for issue 8405.
//
// After flailing around for a while, I discovered that giving the view a layer
// and hiding it while using Metal seems to fix the problem (at least on my iMac).
//
// My fear is that giving it a layer will break random things because that is a
// proud tradition of layers on macOS. Time will tell if that is true.
//
// The test for whether performance is "good" or "bad" is to use the default
// app settings and make a maximized window on a 2014 iMac. Run tests/spam.cc.
// You should get just about 60 fps if it's fast, and 30-45 if it's slow.
+ (BOOL)useLayerForBetterPerformance {
    return ![iTermAdvancedSettingsModel dismemberScrollView];
}

+ (NSSize)charSizeForFont:(NSFont *)aFont
        horizontalSpacing:(CGFloat)hspace
          verticalSpacing:(CGFloat)vspace {
    FontSizeEstimator* fse = [FontSizeEstimator fontSizeEstimatorForFont:aFont];
    NSSize size = [fse size];
    size.width = ceil(size.width);
    size.height = ceil(size.height + [aFont leading]);
    size.width = ceil(size.width * hspace);
    size.height = ceil(size.height * vspace);
    return size;
}

- (instancetype)initWithFrame:(NSRect)aRect {
    self = [super initWithFrame:aRect];
    if (self) {
        // This class has a complicated role.
        //
        // In the old days, it was responsible for drawing and input handling, like a normal view.
        // Then the Metal renderer was added. Input handling logic is complex. This class was made
        // alpha=0 when the Metal view was visible so that it could still receive mouse and keyboard and
        // first responder etc. calls but leave drawing to Metal in a view behind the scrollview.
        //
        // Then it became clear that drawing in this view is fundamentally flawed. That's because
        // almost everything is drawn in here. In particular, top and bottom margins. macOS really
        // wants to cleverly draw a bit above and below the view to optimize scrolling by a small
        // amount, but this is just impossible when you have margins like this view does. We can't
        // overlay views on top of it to hide text that should be obscured by the margins because
        // then transparent backgrounds would not work. The solution is akin to what we do with the
        // Metal view: create a new view that actually draws terminal contents and put it behind the
        // scrollview. Therefore, this view must never draw anything. The glue logic stays put
        // though since this has all the right state for drawing. When the "legacy view" (which
        // actually draws terminal contents when Metal is off) needs to draw it calls in to this
        // view, which performs a draw. Because this is a super-tall view (since it is the
        // scrollview's document view) the coordinate space in this view is different than in the
        // legacy view. The "virtual offset" concept was introduced: this is the difference in
        // coordinate space on the y axis. So the legacy view asks PTYTextView to be drawn in some
        // rect; PTYTextView asks iTermTextDrawingHelper to draw, and provides a virtual offset that
        // shifts all the draws down the Y axis until they will appear in the right place in the
        // legacy view.
        //
        // Virtual offsets are plumbed down to a very low level because I do not trust graphics
        // contexts to do translations. It might work; who knows? But I've been burned enough times
        // to know I want to keep control over this because debugging it will be horrible. So every
        // draw call (NSRectFill, etc.) does a last-second translation by the virtual offset.
        [super setAlphaValue:0];
        _focusFollowsMouse = [[iTermFocusFollowsMouse alloc] init];
        _focusFollowsMouse.delegate = self;
        [_focusFollowsMouse resetMouseLocationToRefuseFirstResponderAt];
        _drawingHelper = [[iTermTextDrawingHelper alloc] init];
        _drawingHelper.delegate = self;

        [self updateMarkedTextAttributes];
        _cursorVisible = YES;
        _selection = [[iTermSelection alloc] init];
        _selection.delegate = self;
        _oldSelection = [_selection copy];
        _drawingHelper.underlinedRange =
            VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
        _timeOfLastBlink = [NSDate timeIntervalSinceReferenceDate];

        // Register for drag and drop.
        [self registerForDraggedTypes: @[
            NSPasteboardTypeFileURL,
            NSPasteboardTypeString ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(useBackgroundIndicatorChanged:)
                                                     name:kUseBackgroundPatternIndicatorChangedNotification
                                                   object:nil];
        [self useBackgroundIndicatorChanged:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(refreshTerminal:)
                                                     name:kRefreshTerminalNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redrawTerminalsNotification:)
                                                     name:iTermChatDatabase.redrawTerminalsNotification
                                                   object:nil];

        _semanticHistoryController = [[iTermSemanticHistoryController alloc] init];
        _semanticHistoryController.delegate = self;

        _urlActionHelper = [[iTermURLActionHelper alloc] initWithSemanticHistoryController:_semanticHistoryController];
        _urlActionHelper.delegate = self;
        _contextMenuHelper = [[iTermTextViewContextMenuHelper alloc] initWithURLActionHelper:_urlActionHelper];
        _urlActionHelper.smartSelectionActionTarget = _contextMenuHelper;

        _fontTable = [[iTermFontTable alloc] init];

        DLog(@"Begin tracking touches in view %@", self);
        self.allowedTouchTypes = NSTouchTypeMaskIndirect;
        [self setWantsRestingTouches:YES];
        threeFingerTapGestureRecognizer_ =
            [[ThreeFingerTapGestureRecognizer alloc] initWithTarget:self
                                                           selector:@selector(threeFingerTap:)];

        [self viewDidChangeBackingProperties];
        _indicatorsHelper = [[iTermIndicatorsHelper alloc] init];
        _indicatorsHelper.delegate = self;

        _selectionScrollHelper = [[iTermSelectionScrollHelper alloc] init];
        _selectionScrollHelper.delegate = self;

        _findOnPageHelper = [[iTermFindOnPageHelper alloc] init];
        _findOnPageHelper.delegate = self;

        _accessibilityHelper = [[iTermTextViewAccessibilityHelper alloc] init];
        _accessibilityHelper.delegate = self;

        _badgeLabel = [[iTermBadgeLabel alloc] init];
        _badgeLabel.delegate = self;

        [_focusFollowsMouse refuseFirstResponderAtCurrentMouseLocation];

        _scrollAccumulator = [[iTermScrollAccumulator alloc] init];

        _horizontalScrollAccumulator = [[iTermScrollAccumulator alloc] init];
        _horizontalScrollAccumulator.sensitivity = [iTermAdvancedSettingsModel horizontalScrollingSensitivity];
        _horizontalScrollAccumulator.isVertical = NO;

        _keyboardHandler = [[iTermKeyboardHandler alloc] init];
        _keyboardHandler.delegate = self;

        _mouseHandler =
        [[PTYMouseHandler alloc] initWithSelectionScrollHelper:_selectionScrollHelper
                               threeFingerTapGestureRecognizer:threeFingerTapGestureRecognizer_
                                     pointerControllerDelegate:self
                     mouseReportingFrustrationDetectorDelegate:self];
        _mouseHandler.mouseDelegate = self;
        _notes = [[NSMutableArray alloc] init];
        _portholes = [[NSMutableArray alloc] init];
        _trackingChildWindows = [[NSMutableArray alloc] init];
        _buttons = [[NSMutableArray alloc] init];
        [self initARC];
    }
    return self;
}

- (void)dealloc {
    [_mouseHandler release];
    [_selection release];
    [_oldSelection release];
    [_smartSelectionRules release];

    [self removeAllTrackingAreas];
    if ([self isFindingCursor]) {
        [self.findCursorWindow close];
    }
    [_findCursorWindow release];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_colorMap release];

    [_fontTable release];

    [_markedTextAttributes release];

    [_semanticHistoryController release];

    [cursor_ release];
    [threeFingerTapGestureRecognizer_ disconnectTarget];
    [threeFingerTapGestureRecognizer_ release];

    _indicatorsHelper.delegate = nil;
    [_indicatorsHelper release];
    _selectionScrollHelper.delegate = nil;
    [_selectionScrollHelper release];
    _findOnPageHelper.delegate = nil;
    [_findOnPageHelper release];
    [_drawingHook release];
    _drawingHelper.delegate = nil;
    [_drawingHelper release];
    [_accessibilityHelper release];
    [_badgeLabel release];
    [_quickLookController close];
    [_quickLookController release];
    [_contextMenuHelper release];
    [_highlightedRows release];
    [_scrollAccumulator release];
    [_horizontalScrollAccumulator release];
    [_shadowRateLimit release];
    _keyboardHandler.delegate = nil;
    [_keyboardHandler release];
    _urlActionHelper.delegate = nil;
    [_urlActionHelper release];
    [_indicatorMessagePopoverViewController release];
    [_notes release];
    [_lastUrlActionCanceler release];
    [_portholes release];
    [_portholesNeedUpdatesJoiner release];
    [_trackingChildWindows release];
    [_hoverBlockCopyButton release];
    [_hoverBlockFoldButton release];
    [_buttons release];
    [_selectCommandTimer invalidate];
    [_selectCommandTimer release];
    [_marginColorWidthBuffer release];
    [_marginColorTwiceHeightBuffer release];
    [_focusFollowsMouse release];

    [super dealloc];
}

- (void)setDataSource:(id<PTYTextViewDataSource>)dataSource {
    _dataSource = dataSource;
    if (dataSource) {
        [_colorMap autorelease];
        _colorMap = [_dataSource.colorMap retain];
    }
}

#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<PTYTextView: %p frame=%@ visibleRect=%@ dataSource=%@ delegate=%@ window=%@>",
            self,
            [NSValue valueWithRect:self.frame],
            [NSValue valueWithRect:[self visibleRect]],
            _dataSource,
            _delegate,
            self.window];
}

- (void)changeFont:(id)fontManager {
    if ([[[PreferencePanel sharedInstance] windowIfLoaded] isVisible]) {
        [[PreferencePanel sharedInstance] changeFont:fontManager];
    } else if ([[[PreferencePanel sessionsInstance] windowIfLoaded] isVisible]) {
        [[PreferencePanel sessionsInstance] changeFont:fontManager];
    }
}

#pragma mark - NSResponder

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (self.enclosingScrollView.isHidden) {
        return NO;
    }
    if ([item action] == @selector(paste:)) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        // Check if there is a string type on the pasteboard
        if ([pboard stringForType:NSPasteboardTypeString] != nil) {
            return YES;
        }
        return [[[NSPasteboard generalPasteboard] pasteboardItems] anyWithBlock:^BOOL(NSPasteboardItem *item) {
            return [item stringForType:(NSString *)kUTTypeUTF8PlainText] != nil;
        }];
    }

    if ([item action] == @selector(pasteOptions:)) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        return [[pboard pasteboardItems] count] > 0;
    }

    if ([item action ] == @selector(cut:)) {
        // Never allow cut.
        return NO;
    }
    if ([item action] == @selector(showHideNotes:)) {
        item.state = [self hasAnyAnnotations] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if ([item action] == @selector(toggleShowTimestamps:)) {
        switch ([self.delegate textviewTimestampsMode]) {
            case iTermTimestampsModeOverlap:
            case iTermTimestampsModeAdjacent:
                item.state = NSControlStateValueOn;
                break;
            case iTermTimestampsModeOff:
                item.state = NSControlStateValueOff;
                break;
            case iTermTimestampsModeHover:
                item.state = NSControlStateValueMixed;
                break;
        }
        return YES;
    }

    if ([item action]==@selector(saveDocumentAs:)) {
        return [self isAnyCharSelected];
    } else if ([item action] == @selector(selectAll:) ||
               [item action]==@selector(installShellIntegration:) ||
               ([item action] == @selector(print:) && [item tag] != 1)) {
        // We always validate the above commands
        return YES;
    }
    if ([item action]==@selector(performFindPanelAction:) && item.tag == NSFindPanelActionShowFindPanel) {
        return YES;
    }

    // NOTE: If you add more methods for copying also update ComposerTextView.
    if ([item action]==@selector(copy:) ||
        [item action]==@selector(copyWithStyles:) ||
        [item action]==@selector(copyWithControlSequences:)) {
        // These commands are allowed only if there is a selection.
        return [self canCopy];
    }
    if (([item action]==@selector(performFindPanelAction:) && item.tag == NSFindPanelActionSetFindString) ||
        ([item action]==@selector(print:) && [item tag] == 1)) { // print selection
        // These commands are allowed only if there is a selection.
        return [_selection hasSelection];
    } else if ([item action]==@selector(pasteSelection:)) {
        return [[iTermController sharedInstance] lastSelectionPromise] != nil && [[iTermController sharedInstance] lastSelectionPromise].maybeError == nil;
    } else if ([item action]==@selector(selectOutputOfLastCommand:)) {
        return [_delegate textViewCanSelectOutputOfLastCommand];
    } else if ([item action]==@selector(selectCurrentCommand:)) {
        return [_delegate textViewCanSelectCurrentCommand];
    }
    if ([item action] == @selector(pasteBase64Encoded:)) {
        return [[NSPasteboard generalPasteboard] dataForFirstFile] != nil;
    }
    if (item.action == @selector(bury:)) {
        return YES;
    }
    if (item.action == @selector(terminalStateToggleAlternateScreen:) ||
        item.action == @selector(terminalStateToggleFocusReporting:) ||
        item.action == @selector(terminalStateToggleMouseReporting:) ||
        item.action == @selector(terminalStateTogglePasteBracketing:) ||
        item.action == @selector(terminalStateToggleApplicationCursor:) ||
        item.action == @selector(terminalStateToggleApplicationKeypad:) ||
        item.action == @selector(terminalToggleKeyboardMode:) ||
        item.action == @selector(terminalStateToggleLiteralMode:)) {
        item.state = [self.delegate textViewTerminalStateForMenuItem:item] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (item.action == @selector(terminalStateSetEmulationLevel:)) {
        item.state = [self.delegate textViewTerminalStateEmulationLevel] == item.tag;
        return YES;
    }
    if (item.action == @selector(terminalStateReset:)) {
        return YES;
    }
    if (item.action == @selector(revealContentNavigationShortcuts:)) {
        return self.findOnPageHelper.searchResults.count > 0;
    }
    if (item.action == @selector(movePane:)) {
        return [[MovePaneController sharedInstance] session] == nil;
    }
    SEL theSel = [item action];
    if ([NSStringFromSelector(theSel) hasPrefix:@"contextMenuAction"]) {
        return YES;
    }
    return [self arcValidateMenuItem:item] || [self swiftValidateMenuItem:item];
}

- (BOOL)it_isTerminalResponder {
    return YES;
}

- (BOOL)resignFirstResponder {
    DLog(@"resign first responder: reset numTouches to 0");
    _mouseHandler.numTouches = 0;
    [_mouseHandler didResignFirstResponder];
    [self removeUnderline];
    [self placeFindCursorOnAutoHide];
    [_delegate textViewDidResignFirstResponder];
    DLog(@"resignFirstResponder %@", self);
    DLog(@"%@", [NSThread callStackSymbols]);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[iTermSecureKeyboardEntryController sharedInstance] update];
    });
    return YES;
}

- (BOOL)becomeFirstResponder {
    DLog(@"%@", [NSThread callStackSymbols]);
    [_mouseHandler didBecomeFirstResponder];
    [_delegate textViewDidBecomeFirstResponder];
    DLog(@"becomeFirstResponder %@", self);
    DLog(@"%@", [NSThread callStackSymbols]);
    [[iTermSecureKeyboardEntryController sharedInstance] update];
    return YES;
}

- (BOOL)scrolledToBottom {
    return (([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / _lineHeight ==
            [_dataSource numberOfLines]);
}

- (void)scrollLineUp:(id)sender {
    [self scrollBy:-[self.enclosingScrollView verticalLineScroll]];
}

- (void)scrollLineDown:(id)sender {
    [self scrollBy:[self.enclosingScrollView verticalLineScroll]];
}

- (void)scrollPageUp:(id)sender {
    [self scrollBy:-self.pageScrollHeight];
}

- (void)scrollPageDown:(id)sender {
    [self scrollBy:self.pageScrollHeight];
}

- (void)scrollHome {
    NSRect scrollRect;

    scrollRect = [self visibleRect];
    scrollRect.origin.y = 0;
    [self scrollRectToVisible:scrollRect];
}

- (void)scrollEnd {
    if ([_dataSource numberOfLines] <= 0) {
      return;
    }
    NSRect lastLine = [self visibleRect];
    lastLine.origin.y = (([_dataSource numberOfLines] - 1) * _lineHeight +
                         [self excess] +
                         _drawingHelper.numberOfIMELines * _lineHeight);
    lastLine.size.height = _lineHeight;
    if (!NSContainsRect(self.visibleRect, lastLine)) {
        [self scrollRectToVisible:lastLine];
    }
}

- (void)flagsChanged:(NSEvent *)theEvent {
    DLog(@"flagsChanged: cmd=%d opt=%d shift=%d ctrl=%d",
          !!(theEvent.it_modifierFlags & NSEventModifierFlagCommand),
          !!(theEvent.it_modifierFlags & NSEventModifierFlagOption),
          !!(theEvent.it_modifierFlags & NSEventModifierFlagShift),
          !!(theEvent.it_modifierFlags & NSEventModifierFlagControl));
    [_delegate textViewDidReceiveFlagsChangedEvent:theEvent];
    [self updateUnderlinedURLs:theEvent];
    NSString *string = [_keyboardHandler.keyMapper keyMapperStringForPreCocoaEvent:theEvent];
    if (string) {
        [_delegate insertText:string];
    }
    [super flagsChanged:theEvent];
}

#pragma mark - NSResponder Keyboard Input and Helpers

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
    DLog(@"performKeyEquivalent self=%@ theEvent=%@", self, theEvent);
    // I disassembled performKeyEquivalent and it just calls
    // performKeyEquivalent on subviews. The only subviews of this view are
    // highlight views or annotation views. This will usually return NO.
    if ([super performKeyEquivalent:theEvent]) {
        NSLog(@"super performed it");
        return YES;
    }
    if (@available(macOS 26, *)) {
        if ([iTermPreferences boolForKey:kPreferenceKeyAllowSymbolicHotKeys] &&
            [iTermSymbolicHotkeys haveBoundKeyForKeycode:theEvent.keyCode modifiers:theEvent.it_modifierFlags]) {
            return NO;
        }
    }
    if (self.window.firstResponder != self) {
        // Don't let it go to the key mapper if I'm not first responder. This
        // is probably a bug in macOS if you get here.
        return NO;
    }

    if ([[NSApp mainMenu] performKeyEquivalent:theEvent]) {
        // Originally I tried to detect when a key would be handled later by a
        // key equivalent by checking if Cmd is pressed, but that doesn't work
        // with the profoundly stupid macOS 15 window tiling shortcuts. They
        // cannot be detected because they misuse the Fn key (for example,
        // control-fn-left is a NSEvent with characters of Home while the key
        // equivalent is Left Arrow). We have to allow them to run, so this is
        // an attempt to handle menu key equivalents a little earlier than they
        // would normally be handled to allow them to work. It works in my
        // testing but only production will tell for sure if it's a bad idea.
        DLog(@"Main menu handled it");
        return YES;
    }
    if ([_keyboardHandler performKeyEquivalent:theEvent inputContext:self.inputContext]) {
        return YES;
    }

    // Backward compatibility hack for cmd-enter to toggle full screen now that the menu item normally
    // uses cmd-ctrl-F.
    const NSEventModifierFlags mask = (NSEventModifierFlagControl |
                                       NSEventModifierFlagCommand |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagOption);
    if ([theEvent.charactersIgnoringModifiers isEqualToString:@"\r"] &&
        (theEvent.modifierFlags & mask) == NSEventModifierFlagCommand &&
        ![[[iTermApplication sharedApplication] delegate] toggleFullScreenHasCmdEnterShortcut]) {
        DLog(@"Perform backward-compatibility toggle fullscreen for cmd-enter on event %@", theEvent);
        [self.window toggleFullScreen:nil];
        return YES;
    }
    return NO;
}

- (void)keyDown:(NSEvent *)event {
    [_mouseHandler keyDown:event];
    [_keyboardHandler keyDown:event inputContext:self.inputContext];
}

- (void)keyUp:(NSEvent *)event {
    [self.delegate keyUp:event];
    [super keyUp:event];
}

- (BOOL)keyIsARepeat {
    return _keyboardHandler.keyIsARepeat;
}

// Compute the length, in _charWidth cells, of the input method text.
- (int)inputMethodEditorLength {
    if (![self hasMarkedText]) {
        return 0;
    }
    NSString* str = [_drawingHelper.markedText string];

    const int maxLen = [str length] * kMaxParts;
    screen_char_t buf[maxLen];
    screen_char_t fg, bg;
    memset(&bg, 0, sizeof(bg));
    memset(&fg, 0, sizeof(fg));
    int len;
    StringToScreenChars(str,
                        buf,
                        fg,
                        bg,
                        &len,
                        [_delegate textViewAmbiguousWidthCharsAreDoubleWidth],
                        NULL,
                        NULL,
                        [_delegate textViewUnicodeNormalizationForm],
                        [_delegate textViewUnicodeVersion],
                        self.dataSource.terminalSoftAlternateScreenMode,
                        NULL);

    // Count how many additional cells are needed due to double-width chars
    // that span line breaks being wrapped to the next line.
    int x = [_dataSource cursorX] - 1;  // cursorX is 1-based
    int width = [_dataSource width];
    if (width == 0 && len > 0) {
        // Width should only be zero in weirdo edge cases, but the modulo below caused crashes.
        return len;
    }
    int extra = 0;
    int curX = x;
    for (int i = 0; i < len; ++i) {
        if (curX == 0 && ScreenCharIsDWC_RIGHT(buf[i])) {
            ++extra;
            ++curX;
        }
        ++curX;
        curX %= width;
    }
    return len + extra;
}

#pragma mark - Scrolling Helpers

- (void)scrollBy:(CGFloat)deltaY {
    NSScrollView *scrollView = self.enclosingScrollView;
    NSRect rect = scrollView.documentVisibleRect;
    NSPoint point;
    point = rect.origin;
    point.y += deltaY;
    [scrollView.documentView scrollPoint:point];
}

- (CGFloat)pageScrollHeight {
    NSRect scrollRect = [self visibleRect];
    return scrollRect.size.height - [[self enclosingScrollView] verticalPageScroll];
}

- (long long)absoluteScrollPosition {
    NSRect visibleRect = [self visibleRect];
    long long localOffset = (visibleRect.origin.y + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]) / [self lineHeight];
    return localOffset + [_dataSource totalScrollbackOverflow];
}

- (void)scrollToAbsoluteOffset:(long long)absOff height:(int)height
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = (absOff - [_dataSource totalScrollbackOverflow]) * _lineHeight - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = _lineHeight * height;
    [self scrollRectToVisible: aFrame];
    [self cancelMomentumScroll];
    [self lockScroll];
}

- (BOOL)withRelativeCoord:(VT100GridAbsCoord)coord
                    block:(void (^ NS_NOESCAPE)(VT100GridCoord coord))block {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    if (coord.y < overflow) {
        return NO;
    }
    if (coord.y - overflow > INT_MAX) {
        return NO;
    }
    VT100GridCoord relative = VT100GridCoordMake(coord.x, coord.y - overflow);
    block(relative);
    return YES;
}

- (BOOL)withRelativeCoordRange:(VT100GridAbsCoordRange)range
                         block:(void (^ NS_NOESCAPE)(VT100GridCoordRange))block {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    VT100GridCoordRange relative = VT100GridCoordRangeFromAbsCoordRange(range, overflow);
    if (relative.start.x < 0) {
        return NO;
    }
    block(relative);
    return YES;
}

- (BOOL)withRelativeWindowedRange:(VT100GridAbsWindowedRange)range
                            block:(void (^ NS_NOESCAPE)(VT100GridWindowedRange))block {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    if (range.coordRange.start.y < overflow || range.coordRange.start.y - overflow > INT_MAX) {
        return NO;
    }
    if (range.coordRange.end.y < overflow || range.coordRange.end.y - overflow > INT_MAX){
        return NO;
    }
    VT100GridWindowedRange relative = VT100GridWindowedRangeFromAbsWindowedRange(range, overflow);
    block(relative);
    return YES;
}

- (void)scrollToSelection {
    if (![_selection hasSelection]) {
        return;
    }
    [self withRelativeCoordRange:[_selection spanningAbsRange] block:^(VT100GridCoordRange range) {
        NSRect aFrame;
        aFrame.origin.x = 0;
        aFrame.origin.y = range.start.y * _lineHeight - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];  // allow for top margin
        aFrame.size.width = [self frame].size.width;
        aFrame.size.height = (range.end.y - range.start.y + 1) * _lineHeight;
        [self cancelMomentumScroll];
        [self lockScroll];
        [self scrollRectToVisible:aFrame];
    }];
}

- (void)cancelMomentumScroll {
    _ignoreMomentumScroll = YES;
}

- (void)lockScroll {
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

- (void)_scrollToLine:(int)line {
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = line * _lineHeight;
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = _lineHeight;
    [self scrollRectToVisible:aFrame];
}

- (void)scrollToCenterLine:(int)line {
    NSRect visible = [self visibleRect];
    int visibleLines = (visible.size.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2) / _lineHeight;
    int lineMargin = (visibleLines - 1) / 2;
    double margin = lineMargin * _lineHeight;

    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = MAX(0, line * _lineHeight - margin);
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = margin * 2 + _lineHeight;
    double end = aFrame.origin.y + aFrame.size.height;
    NSRect total = [self frame];
    if (end > total.size.height) {
        double err = end - total.size.height;
        aFrame.size.height -= err;
    }
    [self scrollRectToVisible:aFrame];
}

- (NSRange)visibleRelativeRange {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    
    // Guard against invalid line height
    if (_lineHeight < 1) {
        return NSMakeRange(NSNotFound, 0);
    }
    
    // Use safe division to avoid overflow/underflow
    BOOL ok = NO;
    const NSInteger firstVisibleLine = iTermSafeDivisionToInteger(visibleRect.origin.y, _lineHeight, &ok);
    if (!ok || firstVisibleLine < 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    
    const NSInteger height = [_dataSource height];
    ITAssertWithMessage(firstVisibleLine < NSIntegerMax - height, @"Addition would overflow: %@ + %@", @(firstVisibleLine), @(height));
    const NSInteger lastVisibleLine = firstVisibleLine + height;
    
    // Ensure the length is non-negative
    const NSInteger length = MAX(0, lastVisibleLine - firstVisibleLine);
    
    const NSRange currentlyVisibleRange = NSMakeRange(firstVisibleLine, length);
    return currentlyVisibleRange;
}

- (NSRange)visibleAbsoluteRangeIncludingOffscreenCommandLineIfVisible:(BOOL)includeOffscreenCommandLine {
    const NSRange relativeRange = [self visibleRelativeRange];
    if (relativeRange.location == NSNotFound) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSRange range = relativeRange;
    range.location += _dataSource.totalScrollbackOverflow;
    if (includeOffscreenCommandLine) {
        return range;
    }
    const int topBottomMargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    if (![_delegate textViewShouldShowOffscreenCommandLineAt:relativeRange.location]) {
        return range;
    }
    if (self.enclosingScrollView.contentView.bounds.origin.y <= topBottomMargin) {
        return range;
    }
    iTermOffscreenCommandLine *offscreenCommandLine = [self.dataSource offscreenCommandLineBefore:range.location - _dataSource.totalScrollbackOverflow];
    if (!offscreenCommandLine) {
        return range;
    }
    const NSRect visibleRect = [self adjustedDocumentVisibleRectIncludingTopMargin:NO];
    const NSRect frame = [iTermTextDrawingHelper offscreenCommandLineFrameForVisibleRect:visibleRect
                                                                                cellSize:NSMakeSize(_charWidth, _lineHeight)
                                                                                gridSize:VT100GridSizeMake(_dataSource.width, _dataSource.height)];
    const int numLines = ceil(frame.size.height / _lineHeight);
    if (range.length <= numLines) {
        return NSMakeRange(range.location, 0);
    }
    return NSMakeRange(range.location + numLines, range.length - numLines);
}

- (void)scrollLineNumberRangeIntoView:(VT100GridRange)range {
    const NSRange desiredRange = NSMakeRange(range.location, range.length);
    const NSRange currentlyVisibleRange = [self visibleRelativeRange];
    if (currentlyVisibleRange.location == NSNotFound) {
        return;
    }
    if (NSIntersectionRange(desiredRange, currentlyVisibleRange).length == MIN(desiredRange.length, currentlyVisibleRange.length)) {
      // Already visible
      return;
    }
    if (range.length < [_dataSource height]) {
        [self scrollToCenterLine:range.location + range.length / 2];
    } else {
        const VT100GridRange rangeOfVisibleLines = [self rangeOfVisibleLines];
        const int currentBottomLine = rangeOfVisibleLines.location + rangeOfVisibleLines.length;
        const int desiredBottomLine = range.length + range.location;
        const int dy = desiredBottomLine - currentBottomLine;
        [self scrollBy:[self.enclosingScrollView verticalLineScroll] * dy];
    }
    [self cancelMomentumScroll];
    [self lockScroll];
}

#pragma mark - NSView

// Overrides an NSView method.
- (NSRect)adjustScroll:(NSRect)proposedVisibleRect {
    proposedVisibleRect.origin.y = (int)(proposedVisibleRect.origin.y / _lineHeight + 0.5) * _lineHeight;
    return proposedVisibleRect;
}

// For Metal
- (void)requestDelegateRedraw {
    [_delegate textViewNeedsDisplayInRect:self.bounds];
}

- (void)removeAllTrackingAreas {
    while (self.trackingAreas.count) {
        [self removeTrackingArea:self.trackingAreas[0]];
    }
}

- (void)viewDidChangeBackingProperties {
    CGFloat scale = [[[self window] screen] backingScaleFactor];
    BOOL isRetina = scale > 1;
    [self setDrawingHelperIsRetina:isRetina];
}

- (void)setDrawingHelperIsRetina:(BOOL)isRetina {
    _drawingHelper.antiAliasedShift = isRetina ? 0.5 : 0;
    _drawingHelper.isRetina = isRetina;
}

- (void)viewWillMoveToWindow:(NSWindow *)win {
    if (!win && [self window]) {
        [self removeAllTrackingAreas];
    }
    [super viewWillMoveToWindow:win];
}

// TODO: Not sure if this is used.
- (BOOL)shouldDrawInsertionPoint {
    return NO;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return NO;
}

- (void)setFrameSize:(NSSize)newSize {
    DLog(@"Set frame size to %@ from\n%@",
          NSStringFromSize(newSize),
          [NSThread callStackSymbols]);
    [super setFrameSize:newSize];
    [self recomputeBadgeLabel];
    [self updatePortholeFrames];
}

#pragma mark Set Needs Display Helpers

- (void)setNeedsDisplayOnLine:(int)line {
    [self requestDelegateRedraw];
}

- (void)setNeedsDisplayOnLine:(int)y inRange:(VT100GridRange)range {
    [self requestDelegateRedraw];
}

- (void)invalidateInputMethodEditorRect {
    if ([_dataSource width] == 0) {
        return;
    }
    [self requestDelegateRedraw];
}

- (void)viewDidMoveToWindow {
    DLog(@"View %@ did move to window %@\n%@", self, self.window, [NSThread callStackSymbols]);
    // If you change tabs while dragging you never get a mouseUp. Issue 8350.
    [_selection endLiveSelection];
    if (self.window == nil) {
        [(NSWindowController *)_shellIntegrationInstallerWindow close];
        _shellIntegrationInstallerWindow = nil;
    }
    [super viewDidMoveToWindow];
}

#pragma mark - NSView Mouse-Related Overrides

- (BOOL)wantsScrollEventsForSwipeTrackingOnAxis:(NSEventGestureAxis)axis {
    return (axis == NSEventGestureAxisHorizontal) ? YES : NO;
}

static NSString *iTermStringForEventPhase(NSEventPhase eventPhase) {
    NSMutableArray<NSString *> *phase = [NSMutableArray array];
    if (eventPhase & NSEventPhaseBegan) {
        [phase addObject:@"Began"];
    }
    if (eventPhase & NSEventPhaseEnded) {
        [phase addObject:@"Ended"];
    }
    if (eventPhase & NSEventPhaseChanged) {
        [phase addObject:@"Changed"];
    }
    if (eventPhase & NSEventPhaseCancelled) {
        [phase addObject:@"Cancelled"];
    }
    if (eventPhase & NSEventPhaseStationary) {
        [phase addObject:@"Stationary"];
    }
    if (eventPhase & NSEventPhaseMayBegin) {
        [phase addObject:@"MayBegin"];
    }
    if (!phase.count) {
        [phase addObject:@"None"];
    }
    return [phase componentsJoinedByString:@"|"];
}

- (void)scrollWheel:(NSEvent *)event {
    DLog(@"scrollWheel: momentumPhase=%@, eventPhase=%@, _ignoreMomentumScroll=%@",
          iTermStringForEventPhase(event.momentumPhase), iTermStringForEventPhase(event.phase), @(_ignoreMomentumScroll));
    if (_ignoreMomentumScroll && event.momentumPhase == NSEventPhaseChanged && event.phase == NSEventPhaseNone) {
        DLog(@"  ignore");
        return;
    }
    _ignoreMomentumScroll = NO;
    DLog(@"scrollWheel:%@", event);
    const NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    if ([_mouseHandler scrollWheel:event pointInView:point]) {
        [super scrollWheel:event];
    }
}

- (void)mouseDown:(NSEvent *)event {
    [_selectCommandTimer invalidate];
    [_selectCommandTimer release];
    _selectCommandTimer = nil;
    
    [self.delegate textViewWillHandleMouseDown:event];
    [_mouseHandler mouseDown:event superCaller:^{ [super mouseDown:event]; }];
}

- (BOOL)mouseDownImpl:(NSEvent *)event {
    return [_mouseHandler mouseDownImpl:event];
}

- (void)mouseUp:(NSEvent *)event {
    [_mouseHandler mouseUp:event];
}

- (BOOL)wantsMouseMovementEvents {
    if (_focusFollowsMouse.haveTrackedMovement) {
        DLog(@"Have a mouse location to refuse first responder at, so track mouse moved");
        return YES;
    }
    const NSEventModifierFlags flags = [[iTermApplication sharedApplication] it_modifierFlags];
    const BOOL commandPressed = (flags & NSEventModifierFlagCommand) != 0;
    if (commandPressed) {
        DLog(@"cmd pressed so track mouse moved");
        return YES;
    }
    if ([self hasUnderline]) {
        DLog(@"have underline so track mouse moved");
        return YES;
    }
    if (_haveVisibleBlock) {
        DLog(@"Have visible blocks");
        return YES;
    }
    if (@available(macOS 11, *)) {
        if ([self hasTerminalButtons]) {
            DLog(@"Have terminal buttons");
            return YES;
        }
    }
    return [_mouseHandler wantsMouseMovementEvents] || [self hasTerminalButtons];
}

- (BOOL)hasTerminalButtons {
    if (@available(macOS 11, *)) {
        return _buttons.count > 0 || _hoverBlockCopyButton != nil || _hoverBlockFoldButton != nil;
    }
    return NO;
}

- (BOOL)mouseIsOverButtonInEvent:(NSEvent *)event {
    if (@available(macOS 11, *)) {
        const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        DLog(@"%@", NSStringFromPoint(point));
        NSArray<iTermTerminalButton *> *buttons = _buttons;
        if (_hoverBlockFoldButton) {
            buttons = [buttons arrayByAddingObject:_hoverBlockFoldButton];
        }
        if (_hoverBlockCopyButton) {
            buttons = [buttons arrayByAddingObject:_hoverBlockCopyButton];
        }
        DLog(@"Mouse at %@", NSStringFromPoint(point));
        return [buttons anyWithBlock:^BOOL(iTermTerminalButton *button) {
            DLog(@"Button %@ at %@", button, NSStringFromRect(button.desiredFrame));
            return NSPointInRect(point, button.desiredFrame);
        }];
    }
    return NO;
}

// If this changes also update -wantsMouseMovementEvents.
- (void)mouseMoved:(NSEvent *)event {
    DLog(@"mouseMoved:%@", event);
    [_focusFollowsMouse mouseMoved:event];
    [self updateUnderlinedURLs:event];
    [self updateButtonHover:event.locationInWindow pressed:!!([NSEvent pressedMouseButtons] & 1)];
    [self updateCursor:event];
    [_mouseHandler mouseMoved:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [self updateButtonHover:event.locationInWindow pressed:YES];
    [_mouseHandler mouseDragged:event];
}

- (void)rightMouseDown:(NSEvent *)event {
    [_mouseHandler rightMouseDown:event
                      superCaller:^{ [super rightMouseDown:event]; }];
}

- (void)rightMouseUp:(NSEvent *)event {
    [_mouseHandler rightMouseUp:event superCaller:^{ [super rightMouseUp:event]; } reportable:[_mouseHandler mouseEventIsReportable:event]];
}

- (void)rightMouseDragged:(NSEvent *)event {
    [_mouseHandler rightMouseDragged:event
                         superCaller:^{ [super rightMouseDragged:event]; }];
}

- (void)otherMouseDown:(NSEvent *)event {
    [_mouseHandler otherMouseDown:event];
}

- (void)otherMouseUp:(NSEvent *)event {
    [_mouseHandler otherMouseUp:event
                    superCaller:^{ [super otherMouseUp:event]; }
                     reportable:[_mouseHandler mouseEventIsReportable:event]];
}

- (void)otherMouseDragged:(NSEvent *)event {
    [_mouseHandler otherMouseDragged:event
                         superCaller:^{ [super otherMouseDragged:event]; }];
}

- (void)touchesBeganWithEvent:(NSEvent *)ev {
    _mouseHandler.numTouches = [[ev touchesMatchingPhase:NSTouchPhaseBegan | NSTouchPhaseStationary
                                                  inView:self] count];
    DLog(@"%@ Begin touch. numTouches_ -> %d", self, _mouseHandler.numTouches);
    [threeFingerTapGestureRecognizer_ touchesBeganWithEvent:ev];
}

- (void)touchesEndedWithEvent:(NSEvent *)ev {
    _mouseHandler.numTouches = [[ev touchesMatchingPhase:NSTouchPhaseStationary
                                                  inView:self] count];
    DLog(@"%@ End touch. numTouches_ -> %d", self, _mouseHandler.numTouches);
    [threeFingerTapGestureRecognizer_ touchesEndedWithEvent:ev];
}

- (void)touchesMovedWithEvent:(NSEvent *)event {
    DLog(@"%@ Move touch.", self);
    [threeFingerTapGestureRecognizer_ touchesMovedWithEvent:event];
}
- (void)touchesCancelledWithEvent:(NSEvent *)event {
    _mouseHandler.numTouches = 0;
    DLog(@"%@ Cancel touch. numTouches_ -> %d", self, _mouseHandler.numTouches);
    [threeFingerTapGestureRecognizer_ touchesCancelledWithEvent:event];
}

- (void)swipeWithEvent:(NSEvent *)event {
    [_mouseHandler swipeWithEvent:event];
}

- (void)pressureChangeWithEvent:(NSEvent *)event {
    [_mouseHandler pressureChangeWithEvent:event];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent {
    return [_mouseHandler acceptsFirstMouse:theEvent];
}

- (void)mouseExited:(NSEvent *)event {
    DLog(@"Mouse exited %@", self);
    if ([_focusFollowsMouse mouseExited:event]) {
        [self requestDelegateRedraw];
    }
    [self updateUnderlinedURLs:event];

    [_hoverBlockCopyButton autorelease];
    _hoverBlockCopyButton = nil;
    [_hoverBlockFoldButton autorelease];
    _hoverBlockFoldButton = nil;
    [_delegate textViewShowHoverURL:nil
                             anchor:VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, -1, -1), -1, -1)];
}

- (void)mouseEntered:(NSEvent *)event {
    DLog(@"Mouse entered %@", self);
    [_mouseHandler mouseEntered:event];

    if ([_focusFollowsMouse mouseWillEnter:event]) {
        [self requestDelegateRedraw];
    }
    [self updateUnderlinedURLs:event];
    NSScrollView *scrollView = self.enclosingScrollView;
    if ([scrollView hitTest:[scrollView convertPoint:event.locationInWindow fromView:nil]] == nil) {
        DLog(@"hitTest at %@ in view (%@ in window) gives nil", NSStringFromPoint([self convertPoint:event.locationInWindow fromView:nil]),
              NSStringFromPoint(event.locationInWindow));
        DLog(@"Event %@ at window coord %@ failed hit test for view with window coords %@",
             event, NSStringFromPoint(event.locationInWindow), NSStringFromRect([self convertRect:self.bounds toView:nil]));
        return;
    }
    [_focusFollowsMouse mouseEntered:event];
}

#pragma mark - NSView Mouse Helpers

- (void)sendFakeThreeFingerClickDown:(BOOL)isDown basedOnEvent:(NSEvent *)event {
    NSEvent *fakeEvent = isDown ? [event mouseDownEventFromGesture] : [event mouseUpEventFromGesture];

    [_mouseHandler performBlockWithThreeTouches:^{
        if (isDown) {
            DLog(@"Emulate three finger click down");
            [self mouseDown:fakeEvent];
            DLog(@"Returned from mouseDown");
        } else {
            DLog(@"Emulate three finger click up");
            [self mouseUp:fakeEvent];
            DLog(@"Returned from mouseDown");
        }
    }];
}

- (void)threeFingerTap:(NSEvent *)ev {
    if (![_mouseHandler threeFingerTap:ev]) {
        [self sendFakeThreeFingerClickDown:YES basedOnEvent:ev];
        [self sendFakeThreeFingerClickDown:NO basedOnEvent:ev];
    }
}

- (BOOL)it_wantsScrollWheelMomentumEvents {
    return [_mouseHandler wantsScrollWheelMomentumEvents];
}

- (void)it_scrollWheelMomentum:(NSEvent *)event {
    DLog(@"Scroll wheel momentum event!");
    [self scrollWheel:event];
}

#pragma mark - NSView Drawing

// We don't draw exactly the document visible rect because there could be scrollback overflow
// accumulated between the last call to -refresh and when it's time to draw. If `userScroll` is
// on then we want to draw the rect you have scrolled to in order to keep it from bouncing around.
// Note also that this excludes the top margin.
- (NSRect)adjustedDocumentVisibleRect {
    return [self adjustedDocumentVisibleRectIncludingTopMargin:NO];
}

- (NSRect)adjustedDocumentVisibleRectIncludingTopMargin:(BOOL)includeTopMargin {
    const BOOL userScroll = [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) userScroll];
    if (!userScroll) {
        const NSRect result = [self bottommostRectExcludingTopMargin:!includeTopMargin];
        DLog(@"User scroll is off so return bottommost rect of %@", NSStringFromRect(result));
        return result;
    }
    const NSRect documentVisibleRect = self.enclosingScrollView.documentVisibleRect;
    const int overflow = [_dataSource scrollbackOverflow];
    const int firstRow = MAX(0, documentVisibleRect.origin.y / _lineHeight - overflow) + _drawingHelper.numberOfIMELines;
    const NSRect result = [self visibleRectExcludingTopMargin:!includeTopMargin
                                                startingAtRow:firstRow];
    DLog(@"adjustedDocumentVisibleRect is %@", NSStringFromRect(result));
    return result;
}

- (CGFloat)virtualOffset {
    const BOOL userScroll = [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) userScroll];
    if (userScroll) {
        const NSRect rectToDraw = [self textDrawingHelperVisibleRectExcludingTopMargin];
        DLog(@"rectToDraw=%@", NSStringFromRect(rectToDraw));
        const CGFloat virtualOffset = NSMinY(rectToDraw) - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
        DLog(@"Draw document visible rect. virtualOffset=%@", @(virtualOffset));
        return virtualOffset;
    }
    // The documentVisibleRect could be wrong if we got more input since -refresh was last
    // called. Force the last lines to be drawn so the screen doesn't appear to jump as in issue
    // 9676.
    const int height = _dataSource.height;
    const CGFloat virtualOffset = (_dataSource.numberOfLines - height + _drawingHelper.numberOfIMELines) * _lineHeight - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    DLog(@"Force draw last rows. numberOfLines=%@ height=%@ lineHeight=%@ bottomMargins=%@ -> virtualOffset=%@",
         @(_dataSource.numberOfLines), @(height), @(_lineHeight), @([iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]), @(virtualOffset));
    return virtualOffset;
}

- (void)smearCursorIfNeededWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper {
    if (!self.animateMovement) {
        DLog(@"Movement animation is off");
        return;
    }
    if (!drawingHelper.cursorIsSolidRectangle) {
        DLog(@"Cursor not a solid rectangle");
        _previousCursorFrame = NSZeroRect;
        return;
    }
    const NSRect cursorFrame = [drawingHelper cursorFrameForSolidRectangle];
    const NSRect documentVisibleRect = [self adjustedDocumentVisibleRectIncludingTopMargin:YES];
    if (_previousCursorFrame.size.width > 0 &&
        cursorFrame.size.width > 0 &&
        !NSEqualRects(cursorFrame, _previousCursorFrame) &&
        NSEqualRects(_previousCursorFrame, NSIntersectionRect(_previousCursorFrame, documentVisibleRect)) &&
        NSEqualRects(cursorFrame, NSIntersectionRect(cursorFrame, documentVisibleRect))) {

        // Convert to visible coordinate space.
        NSRect from = _previousCursorFrame;
        NSRect to = cursorFrame;
        from.origin.y -= documentVisibleRect.origin.y;
        to.origin.y -= documentVisibleRect.origin.y;

        [self.delegate textViewSmearCursorFrom:from
                                            to:to
                                         color:drawingHelper.cursorColor];
    }
    _previousCursorFrame = cursorFrame;
}

// Draw in to another view which exactly coincides with the clip view, except it's inset on the top
// and bottom by the margin heights.
- (void)drawRect:(NSRect)rect inView:(NSView *)view {
    if (![_delegate textViewShouldDrawRect]) {
        // Metal code path in use
        [super drawRect:rect];
        if (![iTermAdvancedSettingsModel disableWindowShadowWhenTransparencyOnMojave]) {
            [self maybeInvalidateWindowShadow];
        }
        return;
    }
    if (_dataSource.width <= 0) {
        ITCriticalError(_dataSource.width < 0, @"Negative datasource width of %@", @(_dataSource.width));
        return;
    }
    DLog(@"drawing document visible rect %@ for %@", NSStringFromRect(self.textDrawingHelperVisibleRectExcludingTopMargin), self);
    DLog(@"numberOfLines=%@", @(self.dataSource.numberOfLines));

    const CGFloat virtualOffset = [self virtualOffset];

    const NSRect *constRectArray;
    NSInteger rectCount;
    [view getRectsBeingDrawn:&constRectArray count:&rectCount];
    NSMutableData *storage = [NSMutableData dataWithLength:sizeof(NSRect) * rectCount];
    NSRect *rectArray = (NSRect *)[storage mutableBytes];
    for (NSInteger i = 0; i < rectCount; i++) {
        rectArray[i] = constRectArray[i];
        rectArray[i].origin.y += virtualOffset;
        DLog(@"rectArray[%@]=%@", @(i), NSStringFromRect(rectArray[i]));
    }

    [self performBlockWithFlickerFixerGrid:^{
        // Initialize drawing helper
        [self drawingHelper];
        DLog(@"draw: minY=%@, absLine=%@",
             @(self.textDrawingHelperVisibleRectExcludingTopMargin.origin.y),
             @([_drawingHelper coordRangeForRect:self.textDrawingHelperVisibleRectExcludingTopMargin].start.y + _dataSource.totalScrollbackOverflow));

        if (_drawingHook) {
            // This is used by tests to customize the draw helper.
            _drawingHook(_drawingHelper);
        }

        NSRect virtualRect = rect;
        virtualRect.origin.y += virtualOffset;

        if (gDebugLogging) {
            DLog(@"DRAW vrect=%@ voff=%@ time=%@ session=%@", NSStringFromRect(virtualRect), @(virtualOffset), @([NSDate timeIntervalSinceReferenceDate]), self.delegate);
        }


        [NSGraphicsContext saveGraphicsState];
        [_drawingHelper drawTextViewContentInRect:virtualRect rectsPtr:rectArray rectCount:rectCount virtualOffset:virtualOffset];

        [NSGraphicsContext restoreGraphicsState];
        const NSRect indicatorsRect = NSRectSubtractingVirtualOffset(_drawingHelper.indicatorFrame, MAX(0, virtualOffset));

        if (!_drawingHelper.offscreenCommandLine) {
            // Draw indicators under timestamps since they take precedence.
            [_indicatorsHelper drawInFrame:indicatorsRect];
        }
        [_drawingHelper drawTimestampsWithVirtualOffset:virtualOffset];
        [_drawingHelper drawOffscreenCommandLineWithVirtualOffset:virtualOffset];
        if (_drawingHelper.offscreenCommandLine) {
            // Draw indicators over offscreen command line so it isn't completely obscured.
            [_indicatorsHelper drawInFrame:indicatorsRect];
        }

        // Not sure why this is needed, but for some reason this view draws over its subviews.
        for (NSView *subview in [self subviews]) {
            [subview setNeedsDisplay:YES];
        }

        if (_drawingHelper.blinkingFound && _blinkAllowed) {
            // The user might have used the scroll wheel to cause blinking text to become
            // visible. Make sure the timer is running if anything onscreen is
            // blinking.
            [self.delegate textViewWillNeedUpdateForBlink];
        }
    }];
    [self maybeInvalidateWindowShadow];
    [self shiftTrackingChildWindows];
    [self smearCursorIfNeededWithDrawingHelper:_drawingHelper];
}

// This view is visible only when annotations are revealed. They are subviews, and while macOS does
// sometimes decide to draw subviews of alpha=0 views, it doesn't always! So we make ourselves
// alpha=1 but clear when an annotation is visible.
- (void)drawRect:(NSRect)rect {
    DLog(@"-[PTYTextView drawRect:]");
    rect = NSIntersectionRect(rect, self.bounds);
    [[NSColor clearColor] set];
    NSRectFillUsingOperation(rect, NSCompositingOperationCopy);
}

// Note that this isn't actually the visible rect because it starts below the top margin.
- (NSRect)textDrawingHelperVisibleRectExcludingTopMargin {
    return [self adjustedDocumentVisibleRectIncludingTopMargin:NO];
}

- (NSRect)textDrawingHelperVisibleRectIncludingTopMargin {
    return [self adjustedDocumentVisibleRectIncludingTopMargin:YES];
}

- (NSRect)bottommostRectExcludingTopMargin:(BOOL)excludeTopMargin {
    const int height = _dataSource.height;
    return [self visibleRectExcludingTopMargin:excludeTopMargin
                                 startingAtRow:_dataSource.numberOfLines - height + _drawingHelper.numberOfIMELines];
}

- (NSRect)visibleRectExcludingTopMargin:(BOOL)excludeTopMargin
                          startingAtRow:(int)row {
    // This is necessary because of the special case in -drawRect:inView:
    NSRect rect = self.enclosingScrollView.documentVisibleRect;
    // Subtract the top margin's height.
    rect.origin.y = row * _lineHeight;
    if (excludeTopMargin) {
        rect.size.height -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    } else {
        rect.origin.y -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    }
    return rect;
}

- (void)performBlockWithFlickerFixerGrid:(void (NS_NOESCAPE ^)(void))block {
    __block PTYTextViewSynchronousUpdateState *originalState = nil;
    [_dataSource performBlockWithSavedGrid:^(id<PTYTextViewSynchronousUpdateStateReading>  _Nullable savedState) {
        if (savedState) {
            originalState = [self syncUpdateState];
            DLog(@"PTYTextView.performBlockWithFlickerFixerGrid: set cusrorVisible=%@", _cursorVisible ? @"true": @"false");
            [self loadSyncUpdateState:savedState];
        } else {
            DLog(@"PTYTextView.performBlockWithFlickerFixerGrid: (no saved grid) cusrorVisible=%@", _cursorVisible ? @"true": @"false");
        }

        block();
    }];
    if (originalState) {
        [self loadSyncUpdateState:originalState];
    }
}

- (void)loadSyncUpdateState:(id<PTYTextViewSynchronousUpdateStateReading>)savedState {
    _cursorVisible = savedState.cursorVisible;
    _drawingHelper.colorMap = savedState.colorMap;
    [_colorMap autorelease];
    _colorMap = [savedState.colorMap retain];
}

- (PTYTextViewSynchronousUpdateState *)syncUpdateState {
    PTYTextViewSynchronousUpdateState *originalState = [[[PTYTextViewSynchronousUpdateState alloc] init] autorelease];
    originalState.colorMap = _colorMap;
    originalState.cursorVisible = _cursorVisible;
    return originalState;
}


- (void)setSuppressDrawing:(BOOL)suppressDrawing {
    if (suppressDrawing == _suppressDrawing) {
        return;
    }
    DLog(@"Set suppressDrawing to %@ from %@", @(suppressDrawing), [NSThread callStackSymbols]);
    _suppressDrawing = suppressDrawing;
    if (PTYTextView.useLayerForBetterPerformance) {
        if (@available(macOS 10.15, *)) {} {
            // Using a layer in a view inside a scrollview is a disaster, per macOS
            // tradition (insane drawing artifacts, especially when scrolling). But
            // not using a layer makes it godawful slow (see note about
            // rdar://45295749). So use a layer when the view is hidden, and
            // remove it when visible.
            if (suppressDrawing) {
                self.layer = [[[CALayer alloc] init] autorelease];
            } else {
                self.layer = nil;
            }
        }
    }
    PTYScrollView *scrollView = (PTYScrollView *)self.enclosingScrollView;
    [scrollView.verticalScroller setNeedsDisplay:YES];
}

- (BOOL)drawingHelperIsValid {
    return _drawingHelper.delegate != nil;
}

- (iTermTextDrawingHelper *)drawingHelper {
    _drawingHelper.showStripes = (_showStripesWhenBroadcastingInput &&
                                  [_delegate textViewSessionIsBroadcastingInput]);
    _drawingHelper.cursorBlinking = [self isCursorBlinking];
    _drawingHelper.excess = [self excess];
    _drawingHelper.selection = _selection;
    _drawingHelper.ambiguousIsDoubleWidth = [_delegate textViewAmbiguousWidthCharsAreDoubleWidth];
    _drawingHelper.normalization = [_delegate textViewUnicodeNormalizationForm];
    _drawingHelper.hasBackgroundImage = [_delegate textViewHasBackgroundImage];
    _drawingHelper.cursorGuideColor = [_delegate textViewCursorGuideColor];
    _drawingHelper.gridSize = VT100GridSizeMake(_dataSource.width, _dataSource.height);
    _drawingHelper.numberOfLines = _dataSource.numberOfLines;
    _drawingHelper.cursorCoord = VT100GridCoordMake(_dataSource.cursorX - 1,
                                                    _dataSource.cursorY - 1);
    _drawingHelper.totalScrollbackOverflow = [_dataSource totalScrollbackOverflow];
    _drawingHelper.numberOfScrollbackLines = [_dataSource numberOfScrollbackLines];
    _drawingHelper.reverseVideo = _dataSource.terminalReverseVideo;
    _drawingHelper.textViewIsActiveSession = [self.delegate textViewIsActiveSession];
    _drawingHelper.textViewIsFirstResponder = self.window.firstResponder == self;
    _drawingHelper.isInKeyWindow = [self isInKeyWindow];
    // Draw the cursor filled in when we're inactive if there's a popup open or key focus was stolen.
    _drawingHelper.shouldDrawFilledInCursor = ([self.delegate textViewShouldDrawFilledInCursor] || _focusFollowsMouse.haveStolenFocus);
    _drawingHelper.isFrontTextView = (self == [[iTermController sharedInstance] frontTextView]);
    _drawingHelper.transparencyAlpha = [self transparencyAlpha];
    _drawingHelper.now = [NSDate timeIntervalSinceReferenceDate];
    _drawingHelper.drawMarkIndicators = [_delegate textViewShouldShowMarkIndicators];
    _drawingHelper.thinStrokes = _thinStrokes;
    _drawingHelper.showSearchingCursor = _showSearchingCursor;
    _drawingHelper.baselineOffset = [self minimumBaselineOffset];
    _drawingHelper.underlineOffset = [self minimumUnderlineOffset];
    _drawingHelper.boldAllowed = _useBoldFont;
    _drawingHelper.italicAllowed = _useItalicFont;
    _drawingHelper.fontProvider = _fontTable.fontProvider;
    _drawingHelper.unicodeVersion = [_delegate textViewUnicodeVersion];
    _drawingHelper.asciiLigatures = _fontTable.anyASCIIDefaultLigatures || _asciiLigatures;
    _drawingHelper.nonAsciiLigatures = _fontTable.anyNonASCIIDefaultLigatures || _nonAsciiLigatures;
    _drawingHelper.copyMode = _delegate.textViewCopyMode;
    _drawingHelper.copyModeSelecting = _delegate.textViewCopyModeSelecting;
    _drawingHelper.copyModeCursorCoord = _delegate.textViewCopyModeCursorCoord;
    _drawingHelper.passwordInput = ([self isInKeyWindow] &&
                                    [_delegate textViewIsActiveSession] &&
                                    _delegate.textViewPasswordInput);
    _drawingHelper.useNativePowerlineGlyphs = self.useNativePowerlineGlyphs;
    _drawingHelper.badgeTopMargin = [_delegate textViewBadgeTopMargin];
    _drawingHelper.badgeRightMargin = [_delegate textViewBadgeRightMargin];
    _drawingHelper.forceAntialiasingOnRetina = [iTermAdvancedSettingsModel forceAntialiasingOnRetina];
    _drawingHelper.blend = MIN(MAX(0.05, [_delegate textViewBlend]), 1);
    _drawingHelper.shouldShowTimestamps = self.showTimestamps;
    _drawingHelper.colorMap = _colorMap;
    _drawingHelper.softAlternateScreenMode = self.dataSource.terminalSoftAlternateScreenMode;
    _drawingHelper.useSelectedTextColor = self.delegate.textViewShouldUseSelectedTextColor;
    _drawingHelper.fontTable = self.fontTable;
    const BOOL autoComposerOpen = [self.delegate textViewIsAutoComposerOpen];
    _drawingHelper.isCursorVisible = _cursorVisible && !autoComposerOpen;
    _drawingHelper.linesToSuppress = self.delegate.textViewLinesToSuppressDrawing;
    _drawingHelper.pointsOnBottomToSuppressDrawing = self.delegate.textViewPointsOnBottomToSuppressDrawing;
    _drawingHelper.extraMargins = self.delegate.textViewExtraMargins;
    _drawingHelper.forceRegularBottomMargin = autoComposerOpen;
    // TODO: Don't leave find on page helper as the source of truth for this!
    _drawingHelper.selectedCommandRegion = [self relativeRangeFromAbsLineRange:self.findOnPageHelper.absLineRange];
    _drawingHelper.kittyImageDraws = [self.dataSource kittyImageDraws];
    const VT100GridRange range = [self rangeOfVisibleLines];
    _drawingHelper.folds = [self.dataSource foldsInRange:range];
    _drawingHelper.rightExtra = self.delegate.textViewRightExtra;
    _drawingHelper.highlightedBlockLineRange = _hoverBlockFoldButton ? [self relativeRangeFromAbsLineRange:_hoverBlockFoldButton.absLineRange] : NSMakeRange(NSNotFound, 0);
    _drawingHelper.timestampBaseline = _timestampBaseline;
    _drawingHelper.marginColor = _marginColor;

    [_drawingHelper updateCachedMetrics];
    if (@available(macOS 11, *)) {
        [self updateTooltipsForButtons:[_drawingHelper updateButtonFrames]];
    }

    const int topBottomMargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    if ([_delegate textViewShouldShowOffscreenCommandLineAt:range.location] &&
        self.enclosingScrollView.contentView.bounds.origin.y > topBottomMargin) {
        _drawingHelper.offscreenCommandLine = [self.dataSource offscreenCommandLineBefore:range.location];
    } else {
        _drawingHelper.offscreenCommandLine = nil;
    }

    CGFloat rightMargin = 0;
    if (self.showTimestamps) {
        [_drawingHelper createTimestampDrawingHelperWithFont:_fontTable.asciiFont.font];
        rightMargin = _drawingHelper.timestampDrawHelper.maximumWidth + 8;
    }
    _drawingHelper.indicatorFrame = [self configureIndicatorsHelperWithRightMargin:rightMargin];
    [_drawingHelper didFinishSetup];

    return _drawingHelper;
}

- (void)updateTooltipsForButtons:(NSArray<iTermTerminalButton *> *)buttons NS_AVAILABLE_MAC(11_0) {
    if (!buttons.count && _haveTooltips) {
        [self removeAllToolTips];
        _haveTooltips = NO;
        return;
    }
    if ([buttons anyWithBlock:^BOOL(iTermTerminalButton *button) {
        return !NSEqualRects(button.lastTooltipRect, button.desiredFrame);
    }]) {
        DLog(@"Update tooltips");
        [self removeAllToolTips];
        [buttons enumerateObjectsUsingBlock:^(iTermTerminalButton *button, NSUInteger idx, BOOL *stop) {
            [self addToolTipRect:button.desiredFrame owner:button userData:NULL];
            button.lastTooltipRect = button.desiredFrame;
        }];
        _haveTooltips = YES;
    }
}

- (NSRange)relativeRangeFromAbsLineRange:(NSRange)absRange {
    long long first = absRange.location;
    long long last = NSMaxRange(absRange);
    long long offset = _dataSource.totalScrollbackOverflow;
    first -= offset;
    last -= offset;
    first = MAX(0, first);
    last = MAX(first, last);
    return NSMakeRange(first, last - first);
}

- (NSPoint)currentMouseCursorCoordinate:(out BOOL *)validPtr {
    NSEvent *currentEvent = [NSApp currentEvent];
    if (!currentEvent || !self.window) {
        *validPtr = NO;
        return NSZeroPoint;
    }
    NSPoint mouseLocationInWindow = [currentEvent locationInWindow];
    NSPoint mouseLocationInScreen = [[self window] convertPointToScreen:mouseLocationInWindow];

    NSRect viewFrameInWindow = [self frame];
    NSRect viewFrameInScreen = [[self window] convertRectToScreen:viewFrameInWindow];

    *validPtr = NSPointInRect(mouseLocationInScreen, viewFrameInScreen);
    return mouseLocationInWindow;
}

- (NSColor *)defaultBackgroundColor {
    CGFloat alpha = [self useTransparency] ? 1 - _transparency : 1;
    return [[_colorMap processedBackgroundColorForBackgroundColor:[_colorMap colorForKey:kColorMapBackground]] colorWithAlphaComponent:alpha];
}

- (NSColor *)defaultTextColor {
    return [_colorMap processedTextColorForTextColor:[_colorMap colorForKey:kColorMapForeground]
                                 overBackgroundColor:[self defaultBackgroundColor]
                              disableMinimumContrast:NO];
}

- (void)updateMarkedTextAttributes {
    // During initialization, this may be called before the non-ascii font is set so we use a system
    // font as a placeholder.
    NSDictionary *theAttributes =
        @{ NSBackgroundColorAttributeName: [self defaultBackgroundColor] ?: [NSColor blackColor],
           NSForegroundColorAttributeName: [self defaultTextColor] ?: [NSColor whiteColor],
           NSFontAttributeName: _fontTable.defaultNonASCIIFont.font ?: [NSFont systemFontOfSize:12],
           NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle | NSUnderlineByWord) };

    [self setMarkedTextAttributes:theAttributes];
}

- (void)updateScrollerForBackgroundColor {
    PTYScroller *scroller = [_delegate textViewVerticalScroller];
    NSColor *backgroundColor = [_colorMap colorForKey:kColorMapBackground];
    const BOOL isDark = [backgroundColor isDark];

    if (isDark) {
        // Dark background, any theme, any OS version
        scroller.knobStyle = NSScrollerKnobStyleLight;
    } else {
        if (self.effectiveAppearance.it_isDark) {
            // Light background, dark theme — issue 8322
            scroller.knobStyle = NSScrollerKnobStyleDark;
        } else {
            // Light background, light theme
            scroller.knobStyle = NSScrollerKnobStyleDefault;
        }
    }

    // The knob style is used only for overlay scrollers. In the minimal theme, the window decorations'
    // colors are based on the terminal background color. That means the appearance must be changed to get
    // legacy scrollbars to change color.
    if ([self.delegate textViewTerminalBackgroundColorDeterminesWindowDecorationColor]) {
        DLog(@"%@ set scroller appearance using isDark=%@", self, @(isDark));
        scroller.appearance = isDark ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    } else {
        DLog(@"%@ set scroller appearance to nil", self);
        scroller.appearance = nil;
    }
}

// Number of extra lines below the last line of text that are always the background color.
// This is 2 except for just after the frame has changed and things are resizing.
- (double)excess {
    NSRect visibleRectExcludingTopAndBottomMargins = [self scrollViewContentSize];
    visibleRectExcludingTopAndBottomMargins.size.height -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2;  // Height without top and bottom margins.
    int rows = visibleRectExcludingTopAndBottomMargins.size.height / _lineHeight;
    double heightOfTextRows = rows * _lineHeight;
    const CGFloat bottomMarginHeight = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    const CGFloat visibleHeightExceptTopMargin = NSHeight(visibleRectExcludingTopAndBottomMargins) + bottomMarginHeight;
    return MAX(visibleHeightExceptTopMargin - heightOfTextRows,
               bottomMarginHeight);  // Never have less than VMARGIN excess, but it can be more (if another tab has a bigger font)
}

- (void)maybeInvalidateWindowShadow {
    if (@available(macOS 10.16, *)) {
        return;
    }
    const double invalidateFPS = [iTermAdvancedSettingsModel invalidateShadowTimesPerSecond];
    if (invalidateFPS > 0) {
        if (self.transparencyAlpha < 1) {
            if ([self.window conformsToProtocol:@protocol(PTYWindow)]) {
                if (_shadowRateLimit == nil) {
                    _shadowRateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"Shadow"
                                                                    minimumInterval:1.0 / invalidateFPS];
                }
                id<PTYWindow> ptyWindow = (id<PTYWindow>)self.window;
                [_shadowRateLimit performRateLimitedBlock:^{
                    DLog(@"Called");
                    [ptyWindow it_setNeedsInvalidateShadow];
                }];
            }
        }
    }
}

- (BOOL)getAndResetDrawingAnimatedImageFlag {
    BOOL result = _drawingHelper.animated;
    _drawingHelper.animated = NO;
    return result;
}

- (BOOL)hasUnderline {
    return _drawingHelper.underlinedRange.coordRange.start.x >= 0;
}

// Reset underlined chars indicating cmd-clickable url.
- (BOOL)removeUnderline {
    if (![self hasUnderline]) {
        return NO;
    }
    _drawingHelper.underlinedRange =
        VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
    [self requestDelegateRedraw];  // It would be better to just display the underlined/formerly underlined area.
    return YES;
}

#pragma mark - Indicators

- (NSRect)configureIndicatorsHelperWithRightMargin:(CGFloat)rightMargin {
    NSColor *backgroundColor = [_colorMap colorForKey:kColorMapBackground];
    const BOOL isDark = [backgroundColor isDark];

    [_indicatorsHelper setIndicator:kiTermIndicatorMaximized
                            visible:[_delegate textViewIsMaximized]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kItermIndicatorBroadcastInput
                            visible:[_delegate textViewSessionIsBroadcastingInput]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorCoprocess
                            visible:[_delegate textViewHasCoprocess]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorAlert
                            visible:[_delegate alertOnNextMark]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorAllOutputSuppressed
                            visible:[_delegate textViewSuppressingAllOutput]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorZoomedIn
                            visible:[_delegate textViewIsZoomedIn]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorCopyMode
                            visible:[_delegate textViewCopyMode]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorDebugLogging
                            visible:gDebugLogging
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorFilter
                            visible:[_delegate textViewIsFiltered]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorPinned
                            visible:[_delegate textViewInPinnedHotkeyWindow]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorAIChatLinked
                            visible:[_delegate textViewSessionIsLinkedToAIChat]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorAIChatStreaming
                            visible:[_delegate textViewSessionIsStreamingToAIChat]
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorChannel
                            visible:[_delegate textViewSessionHasChannelParent]
                     darkBackground:isDark];
    const BOOL secureByUser = [[iTermSecureKeyboardEntryController sharedInstance] enabledByUserDefault];
    const BOOL secure = [[iTermSecureKeyboardEntryController sharedInstance] isEnabled];
    const BOOL allowSecureKeyboardEntryIndicator = [iTermAdvancedSettingsModel showSecureKeyboardEntryIndicator];
    [_indicatorsHelper setIndicator:kiTermIndicatorSecureKeyboardEntry_User
                            visible:secure && secureByUser && allowSecureKeyboardEntryIndicator
                     darkBackground:isDark];
    [_indicatorsHelper setIndicator:kiTermIndicatorSecureKeyboardEntry_Forced
                            visible:secure && !secureByUser && allowSecureKeyboardEntryIndicator
                     darkBackground:isDark];
    [_indicatorsHelper configurationDidComplete];
    NSRect rect = self.visibleRect;
    rect.size.width -= rightMargin;
    return rect;
}

- (void)useBackgroundIndicatorChanged:(NSNotification *)notification {
    _showStripesWhenBroadcastingInput = [iTermApplication.sharedApplication delegate].useBackgroundPatternIndicator;
    [self requestDelegateRedraw];
}

#pragma mark - Geometry

- (NSRect)offscreenCommandLineFrameForView:(NSView *)view {
    NSRect base = [iTermTextDrawingHelper offscreenCommandLineFrameForVisibleRect:self.enclosingScrollView.documentVisibleRect
                                                                         cellSize:NSMakeSize(self.charWidth, self.lineHeight)
                                                                         gridSize:VT100GridSizeMake(self.dataSource.width,
                                                                                                    self.dataSource.height)];
    return [self convertRect:base toView:view];
}

- (NSRect)scrollViewContentSize {
    NSRect r = NSMakeRect(0, 0, 0, 0);
    r.size = [[self enclosingScrollView] contentSize];
    return r;
}

- (CGFloat)desiredHeight {
    // Force the height to always be correct
    return ([_dataSource numberOfLines] * _lineHeight +
            [self excess] +
            _drawingHelper.numberOfIMELines * _lineHeight);
}

- (NSPoint)locationInTextViewFromEvent:(NSEvent *)event {
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint locationInTextView = [self convertPoint:locationInWindow fromView:nil];
    locationInTextView.x = ceil(locationInTextView.x);
    locationInTextView.y = ceil(locationInTextView.y);
    // Clamp the y position to be within the view. Sometimes we get events we probably shouldn't.
    locationInTextView.y = MIN(self.frame.size.height - 1,
                               MAX(0, locationInTextView.y));
    return locationInTextView;
}

- (BOOL)coordinateIsInMutableArea:(VT100GridCoord)coord {
    return coord.y >= self.dataSource.numberOfScrollbackLines;
}

- (NSRect)visibleContentRect {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    visibleRect.size.height -= [self excess];
    visibleRect.size.height -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    return visibleRect;
}

- (VT100GridRange)rangeOfVisibleLines {
    NSRect visibleRect = [self visibleContentRect];
    int start = [self coordForPoint:visibleRect.origin allowRightMarginOverflow:NO].y;
    int end = [self coordForPoint:NSMakePoint(0, NSMaxY(visibleRect) - 1) allowRightMarginOverflow:NO].y;
    return VT100GridRangeMake(start, MAX(0, end - start + 1));
}

- (long long)firstVisibleAbsoluteLineNumber {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    long long firstVisibleLine = visibleRect.origin.y / _lineHeight;
    return firstVisibleLine + _dataSource.totalScrollbackOverflow;
}

- (NSRect)gridRect {
    NSRect visibleRect = [self visibleRect];
    int lineStart = [_dataSource numberOfLines] - [_dataSource height];
    int lineEnd = [_dataSource numberOfLines];
    return NSMakeRect(visibleRect.origin.x,
                      lineStart * _lineHeight,
                      visibleRect.origin.x + visibleRect.size.width,
                      (lineEnd - lineStart + 1) * _lineHeight);
}

- (NSRect)rectWithHalo:(NSRect)rect {
    const int kHaloWidth = 4;
    rect.origin.x = rect.origin.x - _charWidth * kHaloWidth;
    rect.origin.y -= _lineHeight;
    rect.size.width = self.frame.size.width + _charWidth * 2 * kHaloWidth;
    rect.size.height += _lineHeight * 2;

    return rect;
}

#pragma mark - Accessors

- (void)setHighlightCursorLine:(BOOL)highlightCursorLine {
    _drawingHelper.highlightCursorLine = highlightCursorLine;
}

- (BOOL)highlightCursorLine {
    return _drawingHelper.highlightCursorLine;
}

- (void)setUseNonAsciiFont:(BOOL)useNonAsciiFont {
    _drawingHelper.useNonAsciiFont = useNonAsciiFont;
    _useNonAsciiFont = useNonAsciiFont;
    [self requestDelegateRedraw];
    [self updateMarkedTextAttributes];
}

- (void)setAntiAlias:(BOOL)asciiAntiAlias nonAscii:(BOOL)nonAsciiAntiAlias {
    _drawingHelper.asciiAntiAlias = asciiAntiAlias;
    _drawingHelper.nonAsciiAntiAlias = nonAsciiAntiAlias;
    [self requestDelegateRedraw];
}

- (void)setUseBoldFont:(BOOL)boldFlag {
    _useBoldFont = boldFlag;
    [self requestDelegateRedraw];
}

- (void)setThinStrokes:(iTermThinStrokesSetting)thinStrokes {
    _thinStrokes = thinStrokes;
    [self requestDelegateRedraw];
}

- (void)setAsciiLigatures:(BOOL)asciiLigatures {
    _asciiLigatures = asciiLigatures;
    [self requestDelegateRedraw];
}

- (void)setNonAsciiLigatures:(BOOL)nonAsciiLigatures {
    _nonAsciiLigatures = nonAsciiLigatures;
    [self requestDelegateRedraw];
}

- (void)setUseItalicFont:(BOOL)italicFlag {
    _useItalicFont = italicFlag;
    [self requestDelegateRedraw];
}


- (void)setUseBoldColor:(BOOL)flag brighten:(BOOL)brighten {
    _useCustomBoldColor = flag;
    _brightenBold = brighten;
    _drawingHelper.useCustomBoldColor = flag;
    [self requestDelegateRedraw];
}

- (void)setBlinkAllowed:(BOOL)value {
    _drawingHelper.blinkAllowed = value;
    _blinkAllowed = value;
    [self requestDelegateRedraw];
}

- (void)setCursorNeedsDisplay {
    [self requestDelegateRedraw];
}

- (void)setCursorType:(ITermCursorType)value {
    _drawingHelper.cursorType = value;
    [self markCursorDirty];
}

- (NSDictionary *)markedTextAttributes {
    return _markedTextAttributes;
}

- (void)setMarkedTextAttributes:(NSDictionary *)attr {
    [_markedTextAttributes autorelease];
    _markedTextAttributes = [attr retain];
}

- (void)configureAsBrowser {
    _charWidthWithoutSpacing = 1.0;
    _charHeightWithoutSpacing = 1.0;
    _horizontalSpacing = 1.0;
    _verticalSpacing = 1.0;
    self.charWidth = 1.0;
    self.lineHeight = 1.0;
    [self didUpdateFont];
}

- (void)setFontTable:(iTermFontTable *)fontTable
   horizontalSpacing:(CGFloat)horizontalSpacing
     verticalSpacing:(CGFloat)verticalSpacing {
    if (_fontTable != nil) {
        [[NSNotificationCenter defaultCenter] postNotificationName:PTYTextViewWillChangeFontNotification object:self];
    }

    NSSize sz = [PTYTextView charSizeForFont:fontTable.fontForCharacterSizeCalculations
                           horizontalSpacing:1.0
                             verticalSpacing:1.0];

    _charWidthWithoutSpacing = sz.width;
    _charHeightWithoutSpacing = sz.height;
    _horizontalSpacing = horizontalSpacing;
    _verticalSpacing = verticalSpacing;
    self.charWidth = ceil(_charWidthWithoutSpacing * horizontalSpacing);
    self.lineHeight = ceil(_charHeightWithoutSpacing * verticalSpacing);

    [_fontTable autorelease];
    _fontTable = [fontTable retain];
    [self didUpdateFont];
}

- (void)didUpdateFont {
    [self updateMarkedTextAttributes];

    NSScrollView* scrollview = [self enclosingScrollView];
    [scrollview setLineScroll:[self lineHeight]];
    [scrollview setPageScroll:2 * [self lineHeight]];
    [self updateNoteViewFrames];
    [self updatePortholeFrames];
    [_delegate textViewFontDidChange];

    // Refresh to avoid drawing before and after resize.
    [self refresh];
    [self requestDelegateRedraw];
}

- (void)setLineHeight:(double)aLineHeight {
    _lineHeight = ceil(aLineHeight);
    _drawingHelper.cellSize = NSMakeSize(_charWidth, _lineHeight);
    _drawingHelper.cellSizeWithoutSpacing = NSMakeSize(_charWidthWithoutSpacing, _charHeightWithoutSpacing);
}

- (void)setCharWidth:(double)width {
    _charWidth = ceil(width);
    _drawingHelper.cellSize = NSMakeSize(_charWidth, _lineHeight);
    _drawingHelper.cellSizeWithoutSpacing = NSMakeSize(_charWidthWithoutSpacing, _charHeightWithoutSpacing);
}

- (void)toggleShowTimestamps:(id)sender {
    [self.delegate textviewToggleTimestampsMode];
}

- (BOOL)mouseIsOverScroller {
    if (!self.window || !self.enclosingScrollView) {
        return NO;
    }
    const NSPoint screenLocation = [NSEvent mouseLocation];
    const NSPoint windowLocation = [self.window convertPointFromScreen:screenLocation];
    const NSPoint location = [self convertPoint:windowLocation fromView:nil];
    const CGFloat hotWidth = 22;  // A strip of this width on the right of the scrollview will be considered over the scroller.
    const NSRect scrollerRectInScrollview = NSMakeRect(NSWidth(self.enclosingScrollView.bounds) - hotWidth, 0, hotWidth, NSHeight(self.enclosingScrollView.bounds));
    const NSRect scrollerRect = [self convertRect:scrollerRectInScrollview fromView:self.enclosingScrollView];
    return NSPointInRect(location, scrollerRect);
}

- (BOOL)showTimestamps {
    switch ([self.delegate textviewTimestampsMode]) {
        case iTermTimestampsModeOverlap:
        case iTermTimestampsModeAdjacent:
            return YES;
        case iTermTimestampsModeOff:
            return NO;
        case iTermTimestampsModeHover:
            return [self mouseIsOverScroller];
    }
    return NO;
}

- (iTermTimestampsMode)timestampsMode {
    return [self.delegate textviewTimestampsMode];
}

- (void)setCursorVisible:(BOOL)cursorVisible {
    DLog(@"setCursorVisible:%@", cursorVisible ? @"true" : @"false");
    [self markCursorDirty];
    _cursorVisible = cursorVisible;
}

- (BOOL)cursorVisible {
    return _cursorVisible;
}

- (CGFloat)minimumBaselineOffset {
    return _fontTable.baselineOffset;
}

- (CGFloat)minimumUnderlineOffset {
    return _fontTable.underlineOffset;
}

- (void)setTransparency:(double)fVal {
    if (_transparency == fVal) {
        return;
    }
    _transparency = fVal;
    [self requestDelegateRedraw];
    [_delegate textViewTransparencyDidChange];
}

- (void)setTransparencyAffectsOnlyDefaultBackgroundColor:(BOOL)value {
    _drawingHelper.transparencyAffectsOnlyDefaultBackgroundColor = value;
    [self requestDelegateRedraw];
}

- (float)blend {
    return _drawingHelper.blend;
}

- (void)setBlend:(float)fVal {
    _drawingHelper.blend = MIN(MAX(0.05, fVal), 1);
    [self requestDelegateRedraw];
}

- (void)setUseSmartCursorColor:(BOOL)value {
    _drawingHelper.useSmartCursorColor = value;
}

- (BOOL)useSmartCursorColor {
    return _drawingHelper.useSmartCursorColor;
}

- (void)setMinimumContrast:(double)value {
    DLog(@"Text view's min contrast for delegate %p is %f", self.delegate, value);
    _drawingHelper.minimumContrast = value;
}

- (BOOL)useTransparency {
    return [_delegate textViewWindowUsesTransparency];
}

- (double)transparencyAlpha {
    if (self.window.isKeyWindow && [iTermPreferences boolForKey:kPreferenceKeyDisableTransparencyForKeyWindow]) {
        return 1;
    }
    return [self useTransparency] ? 1.0 - _transparency : 1.0;
}

#pragma mark - Focus

// This exists to work around an apparent OS bug described in issue 2690. Under some circumstances
// (which I cannot reproduce) the key window will be an NSToolbarFullScreenWindow and the iTermTerminalWindow
// will be one of the main windows. NSToolbarFullScreenWindow doesn't appear to handle keystrokes,
// so they fall through to the main window. We'd like the cursor to blink and have other key-
// window behaviors in this case.
- (BOOL)isInKeyWindow {
    if ([[self window] isKeyWindow]) {
        DLog(@"%@ is key window", self);
        return YES;
    }
    NSWindow *theKeyWindow = [[NSApplication sharedApplication] keyWindow];
    if (!theKeyWindow) {
        DLog(@"There is no key window");
        return NO;
    }
    if (!strcmp("NSToolbarFullScreenWindow", object_getClassName(theKeyWindow))) {
        DLog(@"key window is a NSToolbarFullScreenWindow, using my main window status of %d as key status",
             (int)self.window.isMainWindow);
        return [[self window] isMainWindow];
    }
    return NO;
}

#pragma mark - Blinking

- (BOOL)isCursorBlinking {
    if (_blinkingCursor &&
        [self isInKeyWindow] &&
        [_delegate textViewIsActiveSession]) {
        return YES;
    } else {
        return NO;
    }
}

#pragma mark - Refresh

// WARNING: Do not call this function directly. Call
// -[refresh] instead, as it ensures scrollback overflow
// is dealt with so that this function can dereference
// [_dataSource dirty] correctly.
- (BOOL)updateDirtyRects:(BOOL *)foundDirtyPtr haveScrolled:(BOOL)haveScrolled {
    BOOL anythingIsBlinking = NO;
    BOOL foundDirty = NO;

    // Flip blink bit if enough time has passed. Mark blinking cursor dirty
    // when it blinks.
    BOOL redrawBlink = [self shouldRedrawBlinkingObjects];
    if (redrawBlink) {
        DebugLog(@"Time to redraw blinking objects");
        if (_blinkingCursor && [self isInKeyWindow]) {
            // Blink flag flipped and there is a blinking cursor. Make it redraw.
            [self setCursorNeedsDisplay];
        }
    }
    const int width = [_dataSource width];

    // Any characters that changed selection status since the last update or
    // are blinking should be set dirty.
    anythingIsBlinking = [self _markChangedSelectionAndBlinkDirty:redrawBlink width:width];

    // Copy selection position to detect change in selected chars next call.
    [_oldSelection release];
    _oldSelection = [_selection copy];

    // Redraw lines with dirty characters
    // IMPORTANT NOTE: This only checks the mutable section of the grid, not the visible area!
    const int numberOfLines = _dataSource.numberOfLines;
    int lineStart = numberOfLines - [_dataSource height];
    int lineEnd = [_dataSource numberOfLines];
    // lineStart to lineEnd is the region that is the screen when the scrollbar
    // is at the bottom of the frame.

    long long totalScrollbackOverflow = [_dataSource totalScrollbackOverflow];
    int allDirty = [_dataSource isAllDirty] ? 1 : 0;

    VT100GridCoord cursorPosition = VT100GridCoordMake([_dataSource cursorX] - 1,
                                                       [_dataSource cursorY] - 1);
    int cursorLines[2] = { -1, -1 };
    if (_previousCursorCoord.x != cursorPosition.x ||
        _previousCursorCoord.y - totalScrollbackOverflow != cursorPosition.y) {
        DLog(@"Redraw previous cursor line (%d) and current cursor line (%d)",
             (int)(_previousCursorCoord.y - totalScrollbackOverflow),
             cursorPosition.y);
        const int previous = totalScrollbackOverflow - totalScrollbackOverflow;
        if (previous >= 0 && previous < numberOfLines) {
            cursorLines[0] = lineStart + _previousCursorCoord.y - totalScrollbackOverflow;
        } else {
            cursorLines[0] = lineStart + cursorPosition.y;
        }
        cursorLines[1] = lineStart + cursorPosition.y;

        // Set _previousCursorCoord to new cursor position
        _previousCursorCoord = VT100GridAbsCoordMake(cursorPosition.x,
                                                     cursorPosition.y + totalScrollbackOverflow);
    }

    // Remove results from dirty lines and mark parts of the view as needing display.
    NSMutableIndexSet *cleanLines = [NSMutableIndexSet indexSet];
    const BOOL marginColorChanged = [self updateMarginColor];
    if (allDirty) {
        foundDirty = YES;
        DLog(@"allDirty=YES");
        const NSRange range = NSMakeRange(lineStart + totalScrollbackOverflow,
                                          lineEnd - lineStart);
        [_findOnPageHelper removeHighlightsInRange:range];
        [_findOnPageHelper removeSearchResultsInRange:range];
        [self requestDelegateRedraw];
    } else {
        for (int y = lineStart; y < lineEnd; y++) {
            VT100GridRange range = [_dataSource dirtyRangeForLine:y - lineStart];
            if (y == cursorLines[0] || y == cursorLines[1]) {
                range = VT100GridRangeMake(0, width);
            }
            if (range.length > 0) {
                DLog(@"Line %d is dirty", y);
                foundDirty = YES;
                // TODO: It would be more correct to remove all search results from this point down and reset the cursor location to the start of the first dirty line. VT100Screen.savedFindContextAbsPos can be after some of the dirty cells causing them not to be searched.
                [_findOnPageHelper removeHighlightsInRange:NSMakeRange(y + totalScrollbackOverflow, 1)];
                [_findOnPageHelper removeSearchResultsInRange:NSMakeRange(y + totalScrollbackOverflow, 1)];
                [self setNeedsDisplayOnLine:y inRange:range];
            } else if (!haveScrolled) {
                [cleanLines addIndex:y - lineStart];
            }
        }
        if (marginColorChanged) {
            [self requestDelegateRedraw];
        }
    }

    // Always mark the IME as needing to be drawn to keep things simple.
    if ([self hasMarkedText]) {
        [self invalidateInputMethodEditorRect];
    }

    if (foundDirty) {
        // Dump the screen contents
        DLog(@"Found dirty with delegate %@", _delegate);
        DLog(@"\n%@", [_dataSource debugString]);
    } else {
        DLog(@"Nothing dirty found, delegate=%@", _delegate);
    }

    // Unset the dirty bit for all chars.
    DebugLog(@"updateDirtyRects resetDirty");
    [_dataSource resetDirty];

    if (foundDirty) {
        [_dataSource saveToDvr:cleanLines];
        [_delegate textViewInvalidateRestorableState];
        [_delegate textViewDidFindDirtyRects];
    }

    if (foundDirty && [_dataSource shouldSendContentsChangedNotification]) {
        [_delegate textViewPostTabContentsChangedNotification];
    }

    // If you're viewing the scrollback area and it contains an animated gif it will need
    // to be redrawn periodically. The set of animated lines is added to while drawing and then
    // reset here.
    NSIndexSet *animatedLines = [_dataSource animatedLines];
    [animatedLines enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [self setNeedsDisplayOnLine:idx];
    }];
    [_dataSource resetAnimatedLines];

    if (foundDirtyPtr) {
        *foundDirtyPtr = foundDirty;
    }
    return _blinkAllowed && anythingIsBlinking;
}

- (NSColor *)colorForMargins {
    if (!_marginColor.enabled) {
        return nil;
    }
    const VT100MarginColor defaultBg = {
        .enabled = YES,
        .bgColorCode = 0,
        .bgGreen = 0,
        .bgBlue = 0,
        .bgColorMode = ColorModeAlternate,
    };
    if (VT100MarginColorsEqual(&defaultBg, &_marginColor)) {
        return nil;
    }
    NSColor *unprocessed = [self colorForCode:_marginColor.bgColorCode
                                        green:_marginColor.bgGreen
                                         blue:_marginColor.bgBlue
                                    colorMode:_marginColor.bgColorMode
                                         bold:NO
                                        faint:NO
                                 isBackground:YES];
    return [_colorMap processedBackgroundColorForBackgroundColor:unprocessed];
}

- (BOOL)updateMarginColor {
    const BOOL enabledInSettings = [iTermAdvancedSettingsModel extendBackgroundColorIntoMargins];
    const VT100MarginColor before = _marginColor;
    if (!_marginColorAllowed || !enabledInSettings) {
        _marginColor.enabled = NO;
    } else {
        _marginColor = [self desiredMarginColor];
    }
    if (!VT100MarginColorsEqual(&before, &_marginColor)) {
        [self.delegate textViewMarginColorDidChange];
        return YES;
    } else {
        return NO;
    }
}

// Unconditionally set _marginColor to the currently correct value.
- (VT100MarginColor)desiredMarginColor {
    const int width = _dataSource.width;
    const int height = _dataSource.height;

    if (!_marginColorWidthBuffer) {
        _marginColorWidthBuffer = [[NSMutableData alloc] init];
    }
    if (!_marginColorTwiceHeightBuffer) {
        _marginColorTwiceHeightBuffer = [[NSMutableData alloc] init];
    }
    _marginColorWidthBuffer.length = sizeof(screen_char_t) * width;
    _marginColorTwiceHeightBuffer.length = sizeof(screen_char_t) * height * 2;

    // Collect the colors of the leftmost and rightmost cells on each row into values buffer.
    screen_char_t *buffer = (screen_char_t *)_marginColorWidthBuffer.mutableBytes;
    screen_char_t *values = (screen_char_t *)_marginColorTwiceHeightBuffer.mutableBytes;
    const NSRange visibleLines = [self visibleRelativeRange];
    int numValues = 0;
    for (NSInteger i = 0; i < visibleLines.length; i++) {
        const int line = i + visibleLines.location;
        const screen_char_t *chars = [_dataSource getLineAtIndex:line withBuffer:buffer];
        values[numValues++] = chars[0];
        values[numValues++] = chars[width - 1];
    }

    // Is any given background color at least 90% prevalent?
    screen_char_t dominant = { 0 };
    if ([self findDominantBackgroundColorInCharacters:values count:numValues threshold:0.8 dominantColor:&dominant]) {
        // Yes! Set the margin color.
        return (VT100MarginColor){
            .enabled = YES,
            .bgColorCode = dominant.backgroundColor,
            .bgGreen = dominant.bgGreen,
            .bgBlue = dominant.bgBlue,
            .bgColorMode = dominant.backgroundColorMode
        };
    }
    // No. Do not change the margin color.
    return (VT100MarginColor){
        .enabled = NO
    };
}

- (BOOL)findDominantBackgroundColorInCharacters:(const screen_char_t *)values
                                          count:(int)numValues
                                      threshold:(double)minFraction
                                  dominantColor:(out screen_char_t *)dominantColor {
    if (numValues == 0) {
        return false;
    }

    // Boyer-Moore majority vote: quickly determine if some value occurs at least 50% of the time.
    screen_char_t candidate = {0};
    int counter = 0;

    for (int i = 0; i < numValues; i += 1) {
        if (counter == 0) {
            candidate = values[i];
            counter = 1;
            continue;
        }
        if (BackgroundColorsEqual(candidate, values[i])) {
            ++counter;
        } else {
            --counter;
        }
    }

    /* 2nd pass: confirm required fraction dominance */
    int freq = 0;
    for (size_t i = 0; i < numValues; ++i) {
        if (BackgroundColorsEqual(candidate, values[i])) {
            ++freq;
        }
    }

    const int threshold = ceil(numValues * minFraction);
    if (freq >= threshold) {
        *dominantColor = candidate;
        return YES;
    }
    return NO;
}

- (void)searchForVisibleBlocks {
    BOOL hadVisibleBlock = _haveVisibleBlock;
    _haveVisibleBlock = NO;
    const NSRange visibleLines = [self visibleRelativeRange];
    for (NSInteger i = 0; i < visibleLines.length; i++) {
        NSDictionary<NSNumber *, iTermExternalAttribute *> *attrs = [[self.dataSource externalAttributeIndexForLine:visibleLines.location + i] attributes];
        if (attrs[@0].blockIDList != nil) {
            _haveVisibleBlock = YES;
        }
    }
    if (hadVisibleBlock != _haveVisibleBlock) {
        DLog(@"Have visible blocks did change");
        [self.delegate textViewHaveVisibleBlocksDidChange];
    }
}

// NOTE: May return a negative Y origin.
- (NSRect)rect:(NSRect)rect minusRows:(long long)rows {
    NSScrollView *scrollView = [self enclosingScrollView];
    const CGFloat amount = [scrollView verticalLineScroll] * rows;
    NSRect scrollRect = rect;
    scrollRect.origin.y -= amount;
    return scrollRect;
}

- (void)handleScrollbackOverflow:(int)scrollbackOverflow userScroll:(BOOL)userScroll {
    // Keep correct selection highlighted
    [_selection scrollbackOverflowDidChange];
    [_oldSelection scrollbackOverflowDidChange];

    // Keep the user's current scroll position.
    BOOL canSkipRedraw = NO;
    if (userScroll) {
        // NOTE: visibleRect and documentVisibleRect differ by the size of the top margin.
        // visibleRect.origin.y == documentVisible.rect.origin.y - VMARGIN
        NSRect scrollRect = [self rect:self.visibleRect minusRows:scrollbackOverflow];
        if (scrollRect.origin.y < 0) {
            scrollRect.origin.y = 0;
        } else {
            // No need to redraw the whole screen because nothing is
            // changing because of the scroll.
            canSkipRedraw = YES;
        }
        const NSRect previous = self.enclosingScrollView.documentVisibleRect;
        [self scrollRectToVisible:scrollRect];
        DLog(@"handleScrollbackOverflow:%@ visibleRect %@ -> %@",
             @(scrollbackOverflow),
             NSStringFromRect(previous),
             NSStringFromRect(scrollRect));
    }

    // NOTE: I used to use scrollRect:by: here, and it is faster, but it is
    // absolutely a lost cause as far as correctness goes. When drawRect
    // gets called it needs to take that scrolling (which would happen
    // immediately when scrollRect:by: gets called) into account. Good luck
    // getting that right. I don't *think* it's a meaningful performance issue.
    // Because of a bug, we were always drawing the whole screen anyway. And if
    // the screen has scrolled by less than its height, input is coming in
    // slowly anyway.
    if (!canSkipRedraw) {
        [self requestDelegateRedraw];
    }

    // Move subviews up
    [self updateNoteViewFrames];
    [self updatePortholeFrames];

    // Update find on page
    [_findOnPageHelper overflowAdjustmentDidChange];

    AccLog(@"Post notification: row count changed");
    NSAccessibilityPostNotification(self, NSAccessibilityRowCountChangedNotification);
}

// Update accessibility, to be called periodically.
- (void)refreshAccessibility {
    AccLog(@"Post notification: value changed");
    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
    long long absCursorY = ([_dataSource cursorY] + [_dataSource numberOfLines] +
                            [_dataSource totalScrollbackOverflow] - [_dataSource height]);
    if ([_dataSource cursorX] != _lastAccessibilityCursorX ||
        absCursorY != _lastAccessibiltyAbsoluteCursorY) {
        AccLog(@"Post notification: selected text changed (cursor is now at (%@,%@))", @(_dataSource.cursorX), @(_dataSource.cursorY));
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedTextChangedNotification);
        AccLog(@"Post notification: selected row changed");
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedRowsChangedNotification);
        AccLog(@"Post notification: selected columns changed");
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedColumnsChangedNotification);
        _lastAccessibilityCursorX = [_dataSource cursorX];
        _lastAccessibiltyAbsoluteCursorY = absCursorY;
        if (UAZoomEnabled()) {
            CGRect selectionRect = NSRectToCGRect(
                [self.window convertRectToScreen:[self convertRect:[self cursorFrame] toView:nil]]);
            selectionRect = [self accessibilityConvertScreenRect:selectionRect];
            UAZoomChangeFocus(&selectionRect, &selectionRect, kUAZoomFocusTypeInsertionPoint);
        }
    }
}

// This is called periodically. It updates the frame size, scrolls if needed, ensures selections
// and subviews are positioned correctly in case things scrolled
//
// Returns YES if blinking text or cursor was found.
- (BOOL)refresh {
    DLog(@"PTYTextView refresh called with delegate %@", _delegate);
    if (_dataSource == nil || _delegate == nil || _inRefresh) {
        return YES;
    }
    // Get the number of lines that have disappeared if scrollback buffer is full.
    _inRefresh = YES;
    const VT100SyncResult syncResult = [self.delegate textViewWillRefresh];
    _inRefresh = NO;

    return [self refreshAfterSync:syncResult];
}

- (BOOL)refreshAfterSync:(VT100SyncResult)syncResult {
    DLog(@"PTYTextView refreshAfterSync called with delegate %@", _delegate);
    if (_dataSource == nil || _delegate == nil || _inRefresh) {
        return YES;
    }

    const int scrollbackOverflow = syncResult.overflow;
    const BOOL frameDidChange = [_delegate textViewResizeFrameIfNeeded];

    assert(_delegate != nil);

    // Perform adjustments if lines were lost from the head of the buffer.
    BOOL userScroll = [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) userScroll];
    if (scrollbackOverflow > 0) {
        // -selectionDidChange might get called here, which calls -refresh.
        // Keeping this function safely reentrant is just too difficult.
        _inRefresh = YES;
        [self handleScrollbackOverflow:scrollbackOverflow userScroll:userScroll];
        _inRefresh = NO;
    }

    // Scroll to the bottom if needed.
    if (!userScroll) {
        iTermMetalClipView *clipView = [iTermMetalClipView castFrom:self.enclosingScrollView.contentView];
        [clipView performBlockWithoutShowingOverlayScrollers:^{
            [self scrollEnd];
        }];
    }

    if ([[self subviews] count]) {
        // TODO: Why update notes not in this textview?
        [[NSNotificationCenter defaultCenter] postNotificationName:PTYNoteViewControllerShouldUpdatePosition
                                                            object:nil];
        // Not sure why this is needed, but for some reason this view draws over its subviews.
        for (NSView *subview in [self subviews]) {
            [subview setNeedsDisplay:YES];
        }
    }

    [_delegate textViewDidRefresh];

    // See if any characters are dirty and mark them as needing to be redrawn.
    // Return if anything was found to be blinking.
    __block BOOL foundBlink = NO;
    [self.dataSource performBlockWithSavedGrid:^(id<PTYTextViewSynchronousUpdateStateReading>  _Nullable state) {
        BOOL foundDirty = NO;
        foundBlink = [self updateDirtyRects:&foundDirty haveScrolled:syncResult.haveScrolled] || [self isCursorBlinking];
        // Update accessibility.
        if (foundDirty) {
            [self refreshAccessibility];
        }
        [self searchForVisibleBlocks];
    }];
    if (scrollbackOverflow > 0 || frameDidChange) {
        // Need to redraw locations of search results.
        [self.delegate textViewFindOnPageLocationsDidChange];
    }

    if (_needsUpdateSubviewFrames) {
        [self updateSubviewFrames];
    }
    [self reloadHoverButtons];
    DLog(@"Refresh returning. Frame is now %@", NSStringFromRect(self.frame));
    return foundBlink;
}

- (void)reloadHoverButtons {
    const NSPoint screenPoint = [NSEvent mouseLocation];
    const VT100GridCoord coord = [self coordForMouseLocation:screenPoint];
    if (VT100GridCoordIsValid(coord)) {
        BOOL changed = NO;
        [self updateHoverButtonsForLine:coord.y changed:&changed];
    } else {
        _hoverBlockFoldButton = nil;
    }
}

- (NSString *)foldableBlockIDOnLine:(int)line {
    NSDictionary<NSNumber *, iTermExternalAttribute *> *attrs = [[self.dataSource externalAttributeIndexForLine:line] attributes];
    NSString *block = [[attrs[@0].blockIDList componentsSeparatedByString:iTermExternalAttributeBlockIDDelimiter] firstObject];
    return block;
}

- (NSString *)updateHoverButtonsForLine:(int)line changed:(out BOOL *)changedPtr {
    NSString *block = [self foldableBlockIDOnLine:line];
    const VT100GridCoordRange coordRange = [_dataSource rangeOfBlockWithID:block];
    NSRange absLineRange;
    if (VT100GridCoordIsValid(coordRange.start) && VT100GridCoordIsValid(coordRange.end)) {
        const VT100GridAbsCoordRange absCoordRange = VT100GridAbsCoordRangeFromCoordRange(coordRange, _dataSource.totalScrollbackOverflow);
        absLineRange = NSMakeRange(absCoordRange.start.y,
                                   absCoordRange.end.y - absCoordRange.start.y + 1);
    } else {
        absLineRange = NSMakeRange(NSNotFound, 0);
    }
    // As a side effect update the current blockCopyButton.
    [self updateHoverButtonsForBlockID:block
                                onLine:line
                          absLineRange:absLineRange
                               changed:changedPtr];
    return block;
}

- (void)updateHoverButtonsForBlockID:(NSString *)block
                              onLine:(int)line
                        absLineRange:(NSRange)absLineRange
                             changed:(out BOOL *)changedPtr {
    *changedPtr = NO;
    if (@available(macOS 11, *)) {
        if (!block) {
            if (_hoverBlockCopyButton != nil || _hoverBlockFoldButton != nil) {
                *changedPtr = YES;
            }
            _hoverBlockCopyButton = nil;
            _hoverBlockFoldButton = nil;
        } else {
            if (![_hoverBlockCopyButton.blockID isEqualToString:block]) {
                *changedPtr = YES;
                [self makeBlockCopyButtonForLine:line block:block];
            }
            [self makeOrUpdateBlockFoldButtonForLine:line
                                               block:block
                                        absLineRange:absLineRange
                                             changed:changedPtr];
        }
    }
}

- (void)makeBlockCopyButtonForLine:(int)line block:(NSString *)block NS_AVAILABLE_MAC(11) {
    int i = line;
    while (i > 0 && [[self blockIDsOnLine:i - 1] containsObject:block]) {
        i -= 1;
    }
    _hoverBlockCopyButton = [[iTermTerminalCopyButton alloc] initWithID:-1
                                                                blockID:block
                                                                   mark:nil
                                                                   absY:@(i + _dataSource.totalScrollbackOverflow)
                                                                tooltip:@"Copy block to clipboard"];
    _hoverBlockCopyButton.isFloating = YES;
    __weak __typeof(self) weakSelf = self;
    const long long offset = _dataSource.totalScrollbackOverflow;
    _hoverBlockCopyButton.action = ^(NSPoint locationInWindow) {
        [weakSelf copyBlock:block absLine:line+offset screenCoordinate:[NSEvent mouseLocation]];
    };
}

- (void)makeOrUpdateBlockFoldButtonForLine:(int)line
                                     block:(NSString *)block
                              absLineRange:(NSRange)absLineRange
                                   changed:(out BOOL *)changedPtr NS_AVAILABLE_MAC(11) {
    id<iTermFoldMarkReading> foldMark = [[self.dataSource foldMarksInRange:VT100GridRangeMake(line, 1)] firstObject];
    const BOOL wasFolded = foldMark != nil;
    int i = line;
    while (i > 0 && [[self blockIDsOnLine:i - 1] containsObject:block]) {
        i -= 1;
    }
    if (absLineRange.length < 3 && !wasFolded) {
        if (!_hoverBlockFoldButton) {
            return;
        }
        _hoverBlockFoldButton = nil;
        *changedPtr = YES;
        return;
    }
    if (_hoverBlockFoldButton) {
        const BOOL remake = [self updateHoverBlockFoldButtonWithBlock:block
                                                                absY:i + _dataSource.totalScrollbackOverflow
                                                              folded:wasFolded
                                                        absLineRange:absLineRange
                                                             changed:changedPtr];
        if (!remake) {
            return;
        }
    }
    *changedPtr = YES;
    _hoverBlockFoldButton = [[iTermTerminalFoldBlockButton alloc] initWithID:-1
                                                                     blockID:block
                                                                        mark:nil
                                                                        absY:@(i + _dataSource.totalScrollbackOverflow)
                                                             currentlyFolded:wasFolded
                                                                absLineRange:absLineRange];
    _hoverBlockFoldButton.isFloating = YES;
    __weak __typeof(self) weakSelf = self;
    _hoverBlockFoldButton.action = ^(NSPoint locationInWindow) {
        if (wasFolded) {
            [weakSelf unfoldBlock:block];
        } else {
            [weakSelf foldBlock:block];
        }
        [weakSelf refresh];
    };
}

- (BOOL)updateHoverBlockFoldButtonWithBlock:(NSString *)block
                                       absY:(long long)absY
                                     folded:(BOOL)folded
                               absLineRange:(NSRange)absLineRange
                                    changed:(out BOOL *)changedPtr {
    if (![_hoverBlockCopyButton.blockID isEqualToString:block] ||
        _hoverBlockFoldButton.folded != folded ||
        !NSEqualRanges(_hoverBlockFoldButton.absLineRange, absLineRange)) {
        return YES;
    }
    _hoverBlockFoldButton.absY = @(absY);
    return NO;
}

- (void)updateSubviewFrames {
    if (_inRefresh) {
        _needsUpdateSubviewFrames = YES;
        return;
    }
    _needsUpdateSubviewFrames = NO;
    [self updateNoteViewFrames];
    [self updatePortholeFrames];
    [self requestDelegateRedraw];
}

- (void)markCursorDirty {
    DLog(@"Cursor marked dirty. Schedule redraw.");
    [self requestDelegateRedraw];
}

- (BOOL)shouldRedrawBlinkingObjects {
    // Time to redraw blinking text or cursor?
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double timeDelta = now - _timeOfLastBlink;
    if (timeDelta >= [iTermAdvancedSettingsModel timeBetweenBlinks]) {
        _drawingHelper.blinkingItemsVisible = !_drawingHelper.blinkingItemsVisible;
        _timeOfLastBlink = now;
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)_markChangedSelectionAndBlinkDirty:(BOOL)redrawBlink width:(int)width {
    BOOL anyBlinkers = NO;
    // Visible chars that have changed selection status are dirty
    // Also mark blinking text as dirty if needed
    int lineStart = ([self visibleRect].origin.y + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]) / _lineHeight;  // add VMARGIN because stuff under top margin isn't visible.
    int lineEnd = ceil(([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / _lineHeight);
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [_dataSource numberOfLines]) {
        lineEnd = [_dataSource numberOfLines];
    }
    NSArray<ScreenCharArray *> *lines = nil;
    if (_blinkAllowed) {
        lines = [_dataSource linesInRange:NSMakeRange(lineStart, lineEnd - lineStart)];
    }
    const NSInteger numLines = lines.count;
    DLog(@"Visible lines are [%d,%d)", lineStart, lineEnd);
    for (int y = lineStart, i = 0; y < lineEnd; y++, i++) {
        if (_blinkAllowed && i < numLines) {
            // First, mark blinking chars as dirty.
            const screen_char_t *theLine = lines[i].line;
            for (int x = 0; x < lines[i].length; x++) {
                const BOOL charBlinks = theLine[x].blink;
                anyBlinkers |= charBlinks;
                const BOOL blinked = redrawBlink && charBlinks;
                if (blinked) {
                    NSRect dirtyRect = [self visibleRect];
                    dirtyRect.origin.y = y * _lineHeight;
                    dirtyRect.size.height = _lineHeight;
                    if (gDebugLogging) {
                        DLog(@"Found blinking char on line %d", y);
                    }
                    const NSRect rect = [self rectWithHalo:dirtyRect];
                    DLog(@"Redraw rect for line y=%d i=%d blink: %@", y, i, NSStringFromRect(rect));
                    [self requestDelegateRedraw];
                    break;
                }
            }
        }

        // Now mark chars whose selection status has changed as needing display.
        const long long overflow = _dataSource.totalScrollbackOverflow;
        NSIndexSet *areSelected = [_selection selectedIndexesOnAbsoluteLine:y + overflow];
        NSIndexSet *wereSelected = [_oldSelection selectedIndexesOnAbsoluteLine:y + overflow];
        if (![areSelected isEqualToIndexSet:wereSelected]) {
            // Just redraw the whole line for simplicity.
            NSRect dirtyRect = [self visibleRect];
            dirtyRect.origin.y = y * _lineHeight;
            dirtyRect.size.height = _lineHeight;
            if (gDebugLogging) {
                DLog(@"found selection change on line %d", y);
            }
            [self requestDelegateRedraw];
        }
    }
    return anyBlinkers;
}

#pragma mark - Selection

- (SmartMatch *)smartSelectAtX:(int)x
                             y:(int)y
                            to:(VT100GridWindowedRange *)range
              ignoringNewlines:(BOOL)ignoringNewlines
                actionRequired:(BOOL)actionRequired
               respectDividers:(BOOL)respectDividers {
    VT100GridAbsWindowedRange absRange;
    const long long overflow = _dataSource.totalScrollbackOverflow;
    SmartMatch *match = [_urlActionHelper smartSelectAtAbsoluteCoord:VT100GridAbsCoordMake(x, y + overflow)
                                                                  to:&absRange
                                                    ignoringNewlines:ignoringNewlines
                                                      actionRequired:actionRequired
                                                     respectDividers:respectDividers];
    if (range) {
        *range = VT100GridWindowedRangeFromAbsWindowedRange(absRange, overflow);
    }
    return match;
}

- (VT100GridCoordRange)rangeByTrimmingNullsFromRange:(VT100GridCoordRange)range
                                          trimSpaces:(BOOL)trimSpaces {
    VT100GridCoordRange result = range;
    int width = [_dataSource width];
    int lineY = result.start.y;
    const screen_char_t *line = [_dataSource screenCharArrayForLine:lineY].line;
    while (!VT100GridCoordEquals(result.start, range.end)) {
        if (lineY != result.start.y) {
            lineY = result.start.y;
            line = [_dataSource screenCharArrayForLine:lineY].line;
        }
        if (line[result.start.x].complexChar || line[result.start.x].image) {
            break;
        }
        unichar code = line[result.start.x].code;
        BOOL trim = ((code == 0) ||
                     (trimSpaces && (code == ' ' || code == '\t' || code == TAB_FILLER)));
        if (trim) {
            result.start.x++;
            if (result.start.x == width) {
                result.start.x = 0;
                result.start.y++;
            }
        } else {
            break;
        }
    }

    while (!VT100GridCoordEquals(result.end, result.start)) {
        // x,y is the predecessor of result.end and is the cell to test.
        int x = result.end.x - 1;
        int y = result.end.y;
        if (x < 0) {
            x = width - 1;
            y = result.end.y - 1;
        }
        if (lineY != y) {
            lineY = y;
            line = [_dataSource screenCharArrayForLine:y].line;
        }
        if (line[x].complexChar || line[x].image) {
            break;
        }
        unichar code = line[x].code;
        BOOL trim = ((code == 0) ||
                     (trimSpaces && (code == ' ' || code == '\t' || code == TAB_FILLER)));
        if (trim) {
            result.end = VT100GridCoordMake(x, y);
        } else {
            break;
        }
    }

    return result;
}

- (IBAction)revealContentNavigationShortcuts:(id)sender {
    [self convertVisibleSearchResultsToContentNavigationShortcutsWithAction:iTermContentNavigationActionOpen
                                                                 clearOnEnd:NO];
}

- (IBAction)selectAll:(id)sender {
    NSRange absRangeToSelect;

    if (_findOnPageHelper.absLineRange.length > 0 &&
        _findOnPageHelper.absLineRange.location != NSNotFound) {
        absRangeToSelect = _findOnPageHelper.absLineRange;
    } else {
        const long long overflow = _dataSource.totalScrollbackOverflow;
        absRangeToSelect = NSMakeRange(overflow, [_dataSource numberOfLines]);
    }
    // Set the selection region to the whole text.
    [_selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(0, absRangeToSelect.location)
                                    mode:kiTermSelectionModeCharacter
                                  resume:NO
                                  append:NO];
    [_selection moveSelectionEndpointTo:VT100GridAbsCoordMake([_dataSource width],
                                                              NSMaxRange(absRangeToSelect) - 1)];
    [_selection endLiveSelection];
    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (IBAction)selectCurrentCommand:(id)sender {
    DLog(@"selectCurrentCommand");
    [self selectRange:[_delegate textViewRangeOfCurrentCommand]];
}

- (IBAction)selectOutputOfLastCommand:(id)sender {
    DLog(@"selectOutputOfLastCommand:");
    [self selectRange:[_delegate textViewRangeOfLastCommandOutput]];
}

- (void)selectRange:(VT100GridAbsCoordRange)range {
    DLog(@"The range is %@", VT100GridAbsCoordRangeDescription(range));

    if (range.start.x < 0) {
        DLog(@"Aborting");
        return;
    }

    DLog(@"Total scrollback overflow is %lld", [_dataSource totalScrollbackOverflow]);

    [_selection beginSelectionAtAbsCoord:range.start
                                    mode:kiTermSelectionModeCharacter
                                  resume:NO
                                  append:NO];
    [_selection moveSelectionEndpointTo:range.end];
    [_selection endLiveSelection];
    DLog(@"Done selecting output of last command.");

    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (void)deselect {
    [_selection endLiveSelection];
    [_selection clearSelection];
}

- (NSString *)selectedText {
    return [self selectedTextInSelection:self.selection];
}

- (NSString *)selectedTextInSelection:(iTermSelection *)selection {
    if (selection == self.selection && _contextMenuHelper.savedSelectedText) {
        DLog(@"Returning saved selected text");
        return _contextMenuHelper.savedSelectedText;
    }
    return [self selectedTextCappedAtSize:0 inSelection:selection];
}

- (NSString *)selectedTextCappedAtSize:(int)maxBytes {
    return [self selectedTextCappedAtSize:0 inSelection:self.selection];
}

- (NSString *)selectedTextCappedAtSize:(int)maxBytes inSelection:(iTermSelection *)selection {
    return [self selectedTextWithStyle:iTermCopyTextStylePlainText
                          cappedAtSize:maxBytes
                     minimumLineNumber:0
                            timestamps:NO
                             selection:selection];
}

- (BOOL)_haveShortSelection {
    int width = [_dataSource width];
    return [_selection hasSelection] && [_selection length] <= width;
}

- (BOOL)haveReasonableSelection {
    return [_selection hasSelection] && [_selection length] <= 1000000;
}

- (iTermLogicalMovementHelper *)logicalMovementHelperForCursorCoordinate:(VT100GridCoord)relativeCursorCoord {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    VT100GridAbsCoord cursorCoord = VT100GridAbsCoordMake(relativeCursorCoord.x,
                                                          relativeCursorCoord.y + overflow);
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    iTermLogicalMovementHelper *helper =
    [[iTermLogicalMovementHelper alloc] initWithTextExtractor:extractor
                                                    selection:_selection
                                             cursorCoordinate:cursorCoord
                                                        width:[_dataSource width]
                                                numberOfLines:[_dataSource numberOfLines]
                                      totalScrollbackOverflow:overflow];
    helper.delegate = self.dataSource;
    return [helper autorelease];
}

- (void)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
                  inDirection:(PTYTextViewSelectionExtensionDirection)direction
                           by:(PTYTextViewSelectionExtensionUnit)unit {
    return [self moveSelectionEndpoint:endpoint
                           inDirection:direction
                                    by:unit
                           cursorCoord:[self cursorCoord]];
}

- (void)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
                  inDirection:(PTYTextViewSelectionExtensionDirection)direction
                           by:(PTYTextViewSelectionExtensionUnit)unit
                  cursorCoord:(VT100GridCoord)cursorCoord {
    iTermLogicalMovementHelper *helper = [self logicalMovementHelperForCursorCoordinate:cursorCoord];
    VT100GridAbsCoordRange newRange =
    [helper moveSelectionEndpoint:endpoint
                      inDirection:direction
                               by:unit];

    [self withRelativeCoordRange:newRange block:^(VT100GridCoordRange range) {
        [self scrollLineNumberRangeIntoView:VT100GridRangeMake(range.start.y,
                                                               range.end.y - range.start.y)];
    }];

    // Copy to pasteboard if needed.
    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (BOOL)selectionScrollAllowed {
    return [self.delegate textViewSelectionScrollAllowed];
}

// Returns YES if the selection changed.
- (BOOL)moveSelectionEndpointToX:(int)x Y:(int)y locationInTextView:(NSPoint)locationInTextView {
    if (!_selection.live) {
        return NO;
    }

    DLog(@"Move selection endpoint to %d,%d, coord=%@",
         x, y, [NSValue valueWithPoint:locationInTextView]);
    int width = [_dataSource width];
    if (locationInTextView.y == 0) {
        x = y = 0;
    } else if (locationInTextView.x < [iTermPreferences intForKey:kPreferenceKeySideMargins] && _selection.liveRange.coordRange.start.y < y) {
        // complete selection of previous line
        x = width;
        y--;
    }
    if (y >= [_dataSource numberOfLines]) {
        y = [_dataSource numberOfLines] - 1;
    }
    const BOOL hasColumnWindow = (_selection.liveRange.columnWindow.location > 0 ||
                                  _selection.liveRange.columnWindow.length < width);
    if (hasColumnWindow &&
        !VT100GridRangeContains(_selection.liveRange.columnWindow, x)) {
        DLog(@"Mouse has wandered outside columnn window %@", VT100GridRangeDescription(_selection.liveRange.columnWindow));
        [_selection clearColumnWindowForLiveSelection];
    }
    const BOOL result = [_selection moveSelectionEndpointTo:VT100GridAbsCoordMake(x, y + _dataSource.totalScrollbackOverflow)];
    DLog(@"moveSelectionEndpoint. selection=%@", _selection);
    return result;
}

- (BOOL)growSelectionLeft {
    if (![_selection hasSelection]) {
        return NO;
    }

    [self moveSelectionEndpoint:kPTYTextViewSelectionEndpointStart
                    inDirection:kPTYTextViewSelectionExtensionDirectionLeft
                             by:kPTYTextViewSelectionExtensionUnitWord];

    return YES;
}

- (void)growSelectionRight {
    if (![_selection hasSelection]) {
        return;
    }

    [self moveSelectionEndpoint:kPTYTextViewSelectionEndpointEnd
                    inDirection:kPTYTextViewSelectionExtensionDirectionRight
                             by:kPTYTextViewSelectionExtensionUnitWord];
}

- (BOOL)isAnyCharSelected {
    return [_selection hasSelection];
}

- (NSString *)getWordForX:(int)x
                        y:(int)y
                    range:(VT100GridWindowedRange *)rangePtr
          respectDividers:(BOOL)respectDividers {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    extractor.supportBidi = [iTermPreferences boolForKey:kPreferenceKeyBidi];
    VT100GridCoord coord = VT100GridCoordMake(x, y);
    if (respectDividers) {
        [extractor restrictToLogicalWindowIncludingCoord:coord];
    }
    VT100GridWindowedRange range = [extractor rangeForWordAt:coord  maximumLength:kLongMaximumWordLength];
    if (rangePtr) {
        *rangePtr = range;
    }

    return [extractor contentInRange:range
                   attributeProvider:nil
                          nullPolicy:kiTermTextExtractorNullPolicyTreatAsSpace
                                 pad:YES
                  includeLastNewline:NO
              trimTrailingWhitespace:NO
                        cappedAtSize:-1
                        truncateTail:YES
                   continuationChars:nil
                              coords:nil];
}

- (BOOL)liveSelectionRespectsSoftBoundaries {
    if (_selection.haveClearedColumnWindow) {
        return NO;
    }
    return [[iTermController sharedInstance] selectionRespectsSoftBoundaries];
}

#pragma mark - Copy/Paste

- (void)copySelectionAccordingToUserPreferences {
    DLog(@"copySelectionAccordingToUserPreferences");
    if ([iTermAdvancedSettingsModel copyWithStylesByDefault]) {
        [self copyWithStyles:self];
    } else {
        [self copy:self];
    }
}

- (BOOL)canCopy {
    return [_selection hasSelection] || [self anyPortholeHasSelection] || [self.delegate textViewSelectedCommandMark] != nil;
}

- (void)copy:(id)sender {
    if ([self anyPortholeHasSelection]) {
        [self copyFromPortholeAsPlainText];
        return;
    }
    if (!_selection.hasSelection && [self.delegate textViewSelectedCommandMark] != nil) {
        [self copySelectedCommand];
        return;
    }
    [self copySelection:self.selection];
}

- (void)copySelection:(iTermSelection *)selection {
    DLog(@"-[PTYTextView copy:] called");
    DLog(@"%@", [NSThread callStackSymbols]);

    if ([self selectionIsBig:selection]) {
        [self asynchronouslyVendSelectedTextWithStyle:iTermCopyTextStylePlainText
                                         cappedAtSize:INT_MAX
                                    minimumLineNumber:0
                                            selection:selection];
        return;
    }

    NSString *copyString = [self selectedTextInSelection:selection];
    [self copyString:copyString];

    __weak __typeof(self) weakSelf = self;
    [iTermJSONPrettyPrinter promoteIfJSONWithString:copyString
                                           callback:^{
        [weakSelf.delegate textViewShowJSONPromotion];
    }];
}

- (BOOL)copyString:(NSString *)copyString {
    if ([iTermAdvancedSettingsModel disallowCopyEmptyString] && copyString.length == 0) {
        DLog(@"Disallow copying empty string");
        return NO;
    }
    DLog(@"Will copy this string: “%@”. selection=%@", copyString, _selection);
    if (copyString) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
        [pboard setString:copyString forType:NSPasteboardTypeString];
    }

    [[PasteboardHistory sharedInstance] save:copyString];
    return YES;
}

- (BOOL)copyData:(NSData *)data {
    NSString *maybeString = [data stringWithEncoding:NSUTF8StringEncoding];
    if (maybeString) {
        return [self copyString:maybeString];
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setData:data forType:@"public.data"];
    return YES;
}

- (IBAction)copyWithStyles:(id)sender {
    if ([self anyPortholeHasSelection]) {
        [self copyFromPortholeAsAttributedString];
        return;
    }
    if (!_selection.hasSelection && [self.delegate textViewSelectedCommandMark] != nil) {
        [self copySelectedCommandWithStyles];
        return;
    }
    [self copySelectionWithStyles:self.selection];
}

- (void)copySelectionWithStyles:(iTermSelection *)selection {
    if ([self selectionIsBig:selection]) {
        [self asynchronouslyVendSelectedTextWithStyle:iTermCopyTextStyleAttributed
                                         cappedAtSize:INT_MAX
                                    minimumLineNumber:0
                                            selection:selection];
        return;
    }

    NSPasteboard *pboard = [NSPasteboard generalPasteboard];

    DLog(@"-[PTYTextView copyWithStyles:] called");
    NSAttributedString *copyAttributedString = [self selectedAttributedTextWithPad:NO
                                                                         selection:selection];
    if ([iTermAdvancedSettingsModel disallowCopyEmptyString] &&
        copyAttributedString.length == 0) {
        DLog(@"Disallow copying empty string");
        return;
    }

    DLog(@"Have selected text of length %d. selection=%@", (int)[copyAttributedString length], selection);
    NSMutableArray *types = [NSMutableArray array];
    if (copyAttributedString) {
        [types addObject:NSPasteboardTypeRTF];
    }
    [pboard declareTypes:types owner:self];
    if (copyAttributedString) {
        // I used to convert this to RTF data using
        // RTFFromRange:documentAttributes: but images wouldn't paste right.
        [pboard clearContents];
        [pboard writeObjects:@[ copyAttributedString ]];
    }
    // I used to do
    //   [pboard setString:[copyAttributedString string] forType:NSPasteboardTypeString]
    // but this seems to take precedence over the attributed version for
    // pasting sometimes, for example in TextEdit.
    [[PasteboardHistory sharedInstance] save:[copyAttributedString string]];
}

- (IBAction)copyWithControlSequences:(id)sender {
    if ([self anyPortholeHasSelection]) {
        [self copyFromPortholeWithControlSequences];
        return;
    }
    if (!_selection.hasSelection && [self.delegate textViewSelectedCommandMark] != nil) {
        [self copySelectedCommandWithControlSequences];
        return;
    }
    [self copySelectionWithControlSequences:_selection];
}

- (void)copySelectionWithControlSequences:(iTermSelection *)selection {
    DLog(@"-[PTYTextView copyWithControlSequences:] called");
    DLog(@"%@", [NSThread callStackSymbols]);

    if ([self selectionIsBig:selection]) {
        [self asynchronouslyVendSelectedTextWithStyle:iTermCopyTextStyleWithControlSequences
                                         cappedAtSize:INT_MAX
                                    minimumLineNumber:0
                                            selection:selection];
        return;
    }

    NSString *copyString = [self selectedTextWithStyle:iTermCopyTextStyleWithControlSequences
                                          cappedAtSize:-1
                                     minimumLineNumber:0
                                            timestamps:NO
                                             selection:selection];

    if ([iTermAdvancedSettingsModel disallowCopyEmptyString] && copyString.length == 0) {
        DLog(@"Disallow copying empty string");
        return;
    }
    DLog(@"Have selected text: “%@”. selection=%@", copyString, _selection);
    if (copyString) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:self];
        [pboard setString:copyString forType:NSPasteboardTypeString];
    }

    [[PasteboardHistory sharedInstance] save:copyString];
}

- (void)paste:(id)sender {
    DLog(@"Checking if delegate %@ can paste", _delegate);
    if ([_delegate respondsToSelector:@selector(paste:)]) {
        DLog(@"Calling paste on delegate.");
        [_delegate paste:sender];
        if (!_selection.live && [iTermAdvancedSettingsModel pastingClearsSelection]) {
            [self deselect];
        }
    }
}

- (void)pasteOptions:(id)sender {
    [_delegate pasteOptions:sender];
}

- (void)pasteSelection:(id)sender {
    [_delegate textViewPasteFromSessionWithMostRecentSelection:[sender tag]];
}

- (IBAction)pasteBase64Encoded:(id)sender {
    NSData *data = [[NSPasteboard generalPasteboard] dataForFirstFile];
    if (data) {
        [_delegate pasteString:[data stringWithBase64EncodingWithLineBreak:@"\r"]];
    }
}

- (BOOL)pasteValuesOnPasteboard:(NSPasteboard *)pasteboard cdToDirectory:(BOOL)cdToDirectory {
    // Paste string or filenames in.
    NSArray *types = [pasteboard types];

    if ([types containsObject:NSPasteboardTypeFileURL]) {
        // Filenames were dragged.
        NSArray *filenames = [pasteboard filenamesOnPasteboardWithShellEscaping:YES forPaste:YES];
        if (filenames.count) {
            BOOL pasteNewline = NO;

            NSMutableString *stringToPaste = [NSMutableString string];
            if (cdToDirectory) {
                // cmd-drag: "cd" to dragged directory (well, we assume it's a directory).
                // If multiple files are dragged, balk.
                if (filenames.count > 1) {
                    return NO;
                } else {
                    [stringToPaste appendString:@"cd "];
                    filenames = [filenames mapWithBlock:^NSString *(NSString *filename) {
                        if ([[NSFileManager defaultManager] itemIsDirectory:[filename stringByResolvingSymlinksInPath]]) {
                            return filename;
                        }
                        return [filename stringByDeletingLastPathComponent];
                    }];
                    pasteNewline = YES;
                }
            }

            if (filenames.count >= 1 && [_delegate textViewPasteFiles:filenames]) {
                return YES;
            }
            // Paste filenames separated by spaces.
            [stringToPaste appendString:[filenames componentsJoinedByString:@" "]];
            if (pasteNewline) {
                // For cmd-drag, we append a newline.
                [stringToPaste appendString:@"\r"];
                [_delegate pasteStringWithoutBracketing:stringToPaste];
            } else if (!cdToDirectory) {
                [stringToPaste appendString:@" "];
                [_delegate pasteString:stringToPaste];
            }

            return YES;
        }
    }

    if ([types containsObject:NSPasteboardTypeString]) {
        NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
        if (string.length) {
            [_delegate pasteString:string];
            return YES;
        }
    }

    return NO;
}

#pragma mark - Content

- (NSAttributedString *)attributedContent {
    return [self contentWithAttributes:YES timestamps:NO];
}

- (NSString *)content {
    return [self contentWithAttributes:NO timestamps:NO];
}

- (NSDictionary *(^)(screen_char_t, iTermExternalAttribute *))attributeProviderUsingProcessedColors:(BOOL)processed
                                                                        elideDefaultBackgroundColor:(BOOL)elideDefaultBackgroundColor {
    return [[^NSDictionary *(screen_char_t theChar, iTermExternalAttribute *ea) {
        return [self charAttributes:theChar externalAttributes:ea processed:processed elideDefaultBackgroundColor:elideDefaultBackgroundColor];
    } copy] autorelease];
}

- (id)contentWithAttributes:(BOOL)attributes timestamps:(BOOL)timestamps {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    extractor.addTimestamps = timestamps;
    VT100GridCoordRange theRange = VT100GridCoordRangeMake(0,
                                                           0,
                                                           [_dataSource width],
                                                           [_dataSource numberOfLines] - 1);
    NSDictionary *(^attributeProvider)(screen_char_t, iTermExternalAttribute *) = nil;
    if (attributes) {
        attributeProvider = [self attributeProviderUsingProcessedColors:NO elideDefaultBackgroundColor:NO];
    }
    return [extractor contentInRange:VT100GridWindowedRangeMake(theRange, 0, 0)
                   attributeProvider:attributeProvider
                          nullPolicy:kiTermTextExtractorNullPolicyTreatAsSpace
                                 pad:NO
                  includeLastNewline:YES
              trimTrailingWhitespace:NO
                        cappedAtSize:-1
                        truncateTail:YES
                   continuationChars:nil
                              coords:nil];
}

// Save method
- (void)saveDocumentAs:(id)sender {
    iTermModernSavePanel *aSavePanel = [[[iTermModernSavePanel alloc] init] autorelease];
    aSavePanel.preferredSSHIdentity = SSHIdentity.localhost;

    NSButton *timestampsButton = [[[NSButton alloc] init] autorelease];
    [timestampsButton setButtonType:NSButtonTypeSwitch];
    timestampsButton.title = @"Include timestamps";
    NSString *userDefaultsKey = @"NoSyncSaveWithTimestamps";
    timestampsButton.state = [[NSUserDefaults standardUserDefaults] boolForKey:userDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [timestampsButton sizeToFit];
    [aSavePanel setAccessoryView:timestampsButton];

    NSString *path = @"";
    NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                               NSUserDomainMask,
                                                               YES);
    if ([searchPaths count]) {
        path = [searchPaths objectAtIndex:0];
    }

    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yyyy-MM-dd hh-mm-ss" options:0 locale:nil];
    NSString *formattedDate = [dateFormatter stringFromDate:[NSDate date]];
    // Stupid mac os can't have colons in filenames
    formattedDate = [formattedDate stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *nowStr = [NSString stringWithFormat:@"Log at %@.txt", formattedDate];

    // Show the save panel. The first time it's done set the path, and from then on the save panel
    // will remember the last path you used.tmp
    [NSSavePanel setDirectoryURL:[NSURL fileURLWithPath:path] onceForID:@"saveDocumentAs:" savePanel:aSavePanel];
    aSavePanel.nameFieldStringValue = nowStr;
    __weak __typeof(aSavePanel) weakSavePanel = aSavePanel;
    [aSavePanel beginWithFallbackWindow:self.window handler:^(NSModalResponse result, iTermSavePanelItem *item) {
        __strong __typeof(weakSavePanel) savePanel = weakSavePanel;
        if (!savePanel) {
            return;
        }
        if (result != NSModalResponseOK) {
            return;
        }
        const BOOL wantTimestamps = timestampsButton.state == NSControlStateValueOn;
        [[NSUserDefaults standardUserDefaults] setBool:wantTimestamps forKey:userDefaultsKey];
        [[self dataToSaveWithTimestamps:wantTimestamps] writeToSaveItem:item completionHandler:^(NSError *error) {
            if (error) {
                DLog(@"Beep: can't write to %@", item);
                NSBeep();
            }
        }];
    }];
}

- (NSData *)dataToSaveWithTimestamps:(BOOL)timestamps {
    if (!timestamps) {
        NSString *string = [self selectedText];
        if (!string) {
            string = [self content];
        }

        return [string dataUsingEncoding:[_delegate textViewEncoding]
                     allowLossyConversion:YES];
    }

    return [[self selectedTextWithStyle:iTermCopyTextStylePlainText
                           cappedAtSize:0
                      minimumLineNumber:0
                             timestamps:YES
                              selection:self.selection] dataUsingEncoding:[_delegate textViewEncoding]
            allowLossyConversion:YES];
}

#pragma mark - Miscellaneous Actions

- (IBAction)terminalStateSetEmulationLevel:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}

- (IBAction)terminalStateToggleLiteralMode:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}

- (IBAction)terminalStateToggleAlternateScreen:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleFocusReporting:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleMouseReporting:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateTogglePasteBracketing:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleApplicationCursor:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleApplicationKeypad:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}

- (IBAction)terminalToggleKeyboardMode:(id)sender {
    [self contextMenu:_contextMenuHelper toggleTerminalStateForMenuItem:sender];
}

- (IBAction)terminalStateReset:(id)sender {
    [self.delegate textViewResetTerminal];
}

- (IBAction)movePane:(id)sender {
    [_delegate textViewMovePane];
}

- (IBAction)bury:(id)sender {
    [_delegate textViewBurySession];
}

#pragma mark - Marks

- (void)beginFlash:(NSString *)flashIdentifier {
    if ([flashIdentifier isEqualToString:kiTermIndicatorBell] &&
        [iTermAdvancedSettingsModel traditionalVisualBell]) {
        [_indicatorsHelper beginFlashingFullScreen];
    } else {
        NSColor *backgroundColor = [_colorMap colorForKey:kColorMapBackground];
        const BOOL isDark = [backgroundColor isDark];
        [_indicatorsHelper beginFlashingIndicator:flashIdentifier darkBackground:isDark];
    }
}

- (void)highlightMarkOnLine:(int)line hasErrorCode:(BOOL)hasErrorCode {
    const CGFloat y = line * _lineHeight + NSMinY(self.frame);
    NSView *highlightingView = [[[iTermHighlightRowView alloc] initWithFrame:NSMakeRect(0, y, self.frame.size.width, _lineHeight)] autorelease];
    [highlightingView setWantsLayer:YES];
    [self.enclosingScrollView.documentView addSubview:highlightingView];

    // Set up layer's initial state
    highlightingView.layer.backgroundColor = hasErrorCode ? [[NSColor redColor] CGColor] : [[NSColor blueColor] CGColor];
    highlightingView.layer.opaque = NO;
    highlightingView.layer.opacity = 0.75;

    // Animate it out, removing from superview when complete.
    [CATransaction begin];
    [highlightingView retain];
    [CATransaction setCompletionBlock:^{
        [highlightingView removeFromSuperview];
        [highlightingView release];
    }];
    const NSTimeInterval duration = PTYTextViewHighlightLineAnimationDuration;

    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = (id)@0.75;
    animation.toValue = (id)@0.0;
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.removedOnCompletion = NO;
    animation.fillMode = kCAFillModeForwards;
    [highlightingView.layer addAnimation:animation forKey:@"opacity"];

    [CATransaction commit];

    if (!_highlightedRows) {
        _highlightedRows = [[NSMutableArray alloc] init];
    }

    iTermHighlightedRow *entry = [[iTermHighlightedRow alloc] initWithAbsoluteLineNumber:_dataSource.totalScrollbackOverflow + line
                                                                                 success:!hasErrorCode];
    [_highlightedRows addObject:entry];
    [_delegate textViewDidHighlightMark];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self removeHighlightedRow:entry];
        [entry release];
    });
}

- (void)removeHighlightedRow:(iTermHighlightedRow *)row {
    [_highlightedRows removeObject:row];
}

#pragma mark - Annotations

- (void)addViewForNote:(id<PTYAnnotationReading>)annotation focus:(BOOL)focus visible:(BOOL)visible {
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] initWithAnnotation:annotation] autorelease];
    note.delegate = self;
    [_notes addObject:note];
    // Make sure scrollback overflow is reset.
    if (note.annotation.stringValue.length) {
        [note sizeToFit];
    }
    [self refresh];
    [note.view removeFromSuperview];
    [self addSubview:note.view];
    [self updateNoteViewFrames];
    [note setNoteHidden:!visible];
    if (visible) {
        [self requestDelegateRedraw];
        if (focus) {
            [note makeFirstResponder];
        }
        [self updateAlphaValue];
    }
}

- (void)addNote {
    if (![_selection hasSelection]) {
        return;
    }
    [self withRelativeCoordRange:_selection.lastAbsRange.coordRange block:^(VT100GridCoordRange range) {
        PTYAnnotation *annotation = [[[PTYAnnotation alloc] init] autorelease];
        [_dataSource addNote:annotation inRange:range focus:YES visible:YES];
    }];
}

- (void)showNotes:(id)sender {
}

- (void)updateNoteViewFrames {
    for (PTYNoteViewController *note in _notes) {
        VT100GridCoordRange coordRange = [_dataSource coordRangeOfAnnotation:note.annotation];
        if (coordRange.end.y >= 0) {
            [note setAnchor:NSMakePoint(coordRange.end.x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins],
                                        (1 + coordRange.end.y) * _lineHeight)];
        }
    }
}

- (BOOL)hasAnyAnnotations {
    for (NSView *view in [self subviews]) {
        if ([view isKindOfClass:[PTYNoteView class]]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)anyAnnotationsAreVisible {
    for (NSView *view in [self subviews]) {
        if ([view isKindOfClass:[PTYNoteView class]]) {
            if (!view.hidden) {
                return YES;
            }
        }
    }
    return NO;
}

- (void)showHideNotes:(id)sender {
    [_delegate textViewToggleAnnotations];
}

#pragma mark - Cursor

- (void)updateCursor:(NSEvent *)event {
    [self updateCursorAndUnderlinedRange:event];
}

- (VT100GridCoord)moveCursorHorizontallyTo:(VT100GridCoord)target from:(VT100GridCoord)cursor {
    DLog(@"Moving cursor horizontally from %@ to %@",
         VT100GridCoordDescription(cursor), VT100GridCoordDescription(target));
    VT100Output *terminalOutput = [_dataSource terminalOutput];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    NSComparisonResult initialOrder = VT100GridCoordOrder(cursor, target);
    // Note that we could overshoot the destination because of double-width characters if the target
    // is a DWC_RIGHT.
    while (![extractor coord:cursor isEqualToCoord:target]) {
        switch (initialOrder) {
            case NSOrderedAscending:
                [_delegate writeStringWithLatin1Encoding:[[terminalOutput keyArrowRight:0] stringWithEncoding:NSISOLatin1StringEncoding]];
                cursor = [extractor successorOfCoord:cursor];
                break;

            case NSOrderedDescending:
                [_delegate writeStringWithLatin1Encoding:[[terminalOutput keyArrowLeft:0] stringWithEncoding:NSISOLatin1StringEncoding]];
                cursor = [extractor predecessorOfCoord:cursor];
                break;

            case NSOrderedSame:
                return cursor;
        }
    }
    DLog(@"Cursor will move to %@", VT100GridCoordDescription(cursor));
    return cursor;
}

- (void)placeCursorOnCurrentLineWithEvent:(NSEvent *)event
                               verticalOk:(BOOL)verticalOk {
    DLog(@"PTYTextView placeCursorOnCurrentLineWithEvent BEGIN %@", event);

    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    VT100GridCoord target = VT100GridCoordMake(clickPoint.x, clickPoint.y);
    VT100Output *terminalOutput = [_dataSource terminalOutput];

    VT100GridCoord cursor = VT100GridCoordMake([_dataSource cursorX] - 1,
                                               [_dataSource absoluteLineNumberOfCursor] - [_dataSource totalScrollbackOverflow]);
    if (!verticalOk) {
        DLog(@"Vertical movement not allowed");
        [self moveCursorHorizontallyTo:target from:cursor];
        return;
    }

    if (cursor.x > target.x) {
        DLog(@"Move cursor left before any vertical movement");
        // current position is right of target x,
        // so first move to left, and (if necessary)
        // up or down afterwards
        cursor = [self moveCursorHorizontallyTo:VT100GridCoordMake(target.x, cursor.y)
                                           from:cursor];
    }

    // Move cursor vertically.
    DLog(@"Move cursor vertically from %@ to y=%d", VT100GridCoordDescription(cursor), target.y);
    while (cursor.y != target.y) {
        if (cursor.y > target.y) {
            [_delegate writeStringWithLatin1Encoding:[[terminalOutput keyArrowUp:0] stringWithEncoding:NSISOLatin1StringEncoding]];
            cursor.y--;
        } else {
            [_delegate writeStringWithLatin1Encoding:[[terminalOutput keyArrowDown:0] stringWithEncoding:NSISOLatin1StringEncoding]];
            cursor.y++;
        }
    }

    if (cursor.x != target.x) {
        [self moveCursorHorizontallyTo:target from:cursor];
    }

    DLog(@"PTYTextView placeCursorOnCurrentLineWithEvent END");
}

- (VT100GridCoord)cursorCoord {
    return VT100GridCoordMake(_dataSource.cursorX - 1,
                              _dataSource.numberOfScrollbackLines + _dataSource.cursorY - 1);
}

#pragma mark - Badge

- (void)setBadgeLabel:(NSString *)badgeLabel {
    _badgeLabel.stringValue = badgeLabel;
    [self recomputeBadgeLabel];
}

- (void)recomputeBadgeLabel {
    if (!_delegate) {
        return;
    }

    _badgeLabel.fillColor = [_delegate textViewBadgeColor];
    _badgeLabel.backgroundColor = [_colorMap colorForKey:kColorMapBackground];
    _badgeLabel.viewSize = self.enclosingScrollView.documentVisibleRect.size;
    if (_badgeLabel.isDirty) {
        _badgeLabel.dirty = NO;
        _drawingHelper.badgeImage = [_badgeLabel image];
        [self requestDelegateRedraw];
    }
}

#pragma mark - Semantic History

- (void)setSemanticHistoryPrefs:(NSDictionary *)prefs {
    self.semanticHistoryController.prefs = prefs;
}

- (void)openSemanticHistoryPath:(NSString *)path
                  orRawFilename:(NSString *)rawFileName
                       fragment:(NSString *)fragment
               workingDirectory:(NSString *)workingDirectory
                     lineNumber:(NSString *)lineNumber
                   columnNumber:(NSString *)columnNumber
                         prefix:(NSString *)prefix
                         suffix:(NSString *)suffix
                     completion:(void (^)(BOOL))completion {
    [_urlActionHelper openSemanticHistoryPath:path
                                orRawFilename:rawFileName
                                     fragment:fragment
                             workingDirectory:workingDirectory
                                   lineNumber:lineNumber
                                 columnNumber:columnNumber
                                       prefix:prefix
                                       suffix:suffix
                                   completion:completion];
}

- (BOOL)showCommandInfoForEvent:(NSEvent *)event {
    if (event.buttonNumber == 1) {
        iTermOffscreenCommandLine *offscreenCommandLine = [self offscreenCommandLineForClickAt:event.locationInWindow];
        if (offscreenCommandLine) {
            [self presentCommandInfoForOffscreenCommandLine:offscreenCommandLine event:event fromOffscreenCommandLine:YES];
            return YES;
        }
    }
    id<VT100ScreenMarkReading> mark = [_contextMenuHelper markForClick:event requireMargin:event.buttonNumber == 1];
    return [self showCommandInfoForMark:mark at:event.locationInWindow];
}

- (BOOL)showCommandInfoForMark:(id<VT100ScreenMarkReading>)mark at:(NSPoint)locationInWindow {
    if (mark.startDate != nil) {
        const VT100GridCoord coord = [self coordForPointInWindow:locationInWindow];
        const long long overflow = [self.dataSource totalScrollbackOverflow];
        NSDate *date = [self.dataSource timestampForLine:coord.y];
        [self presentCommandInfoForMark:mark
                     absoluteLineNumber:VT100GridAbsCoordFromCoord(coord, overflow).y
                                   date:date
                                  point:locationInWindow
               fromOffscreenCommandLine:NO];
        return YES;
    }
    return NO;
}

- (NSMenu *)titleBarMenu {
    return [_contextMenuHelper titleBarMenu];
}

#pragma mark - Drag and Drop

//
// Called when our drop area is entered
//
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    // NOTE: draggingUpdated: calls this method because they need the same implementation.
    int numValid = -1;
    if ([NSEvent modifierFlags] & NSEventModifierFlagOption) {  // Option-drag to copy
        _drawingHelper.showDropTargets = YES;
        [self.delegate textViewDidUpdateDropTargetVisibility];
    }
    NSDragOperation operation = [self dragOperationForSender:sender numberOfValidItems:&numValid];
    if (numValid != sender.numberOfValidItemsForDrop) {
        sender.numberOfValidItemsForDrop = numValid;
    }
    [self requestDelegateRedraw];
    return operation;
}

- (void)draggingExited:(nullable id <NSDraggingInfo>)sender {
    _drawingHelper.showDropTargets = NO;
    [self.delegate textViewDidUpdateDropTargetVisibility];
    [self requestDelegateRedraw];
}

//
// Called when the dragged object is moved within our drop area
//
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
    NSPoint windowDropPoint = [sender draggingLocation];
    NSPoint dropPoint = [self convertPoint:windowDropPoint fromView:nil];
    int dropLine = dropPoint.y / _lineHeight;
    if (dropLine != _drawingHelper.dropLine) {
        _drawingHelper.dropLine = dropLine;
        [self requestDelegateRedraw];
    }
    return [self draggingEntered:sender];
}

//
// Called when the dragged item is about to be released in our drop area.
//
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    BOOL result;

    // Check if parent NSTextView knows how to handle this.
    result = [super prepareForDragOperation: sender];

    // If parent class does not know how to deal with this drag type, check if we do.
    if (result != YES &&
        [self dragOperationForSender:sender] != NSDragOperationNone) {
        result = YES;
    }

    return result;
}

// Returns the drag operation to use. It is determined from the type of thing
// being dragged, the modifiers pressed, and where it's being dropped.
- (NSDragOperation)dragOperationForSender:(id<NSDraggingInfo>)sender
                       numberOfValidItems:(int *)numberOfValidItemsPtr {
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray *types = [pb types];
    NSPoint windowDropPoint = [sender draggingLocation];
    NSPoint dropPoint = [self convertPoint:windowDropPoint fromView:nil];
    int dropLine = dropPoint.y / _lineHeight;
    SCPPath *dropScpPath = [_dataSource scpPathForFile:@"" onLine:dropLine];

    // It's ok to upload if a file is being dragged in and the drop location has a remote host path.
    BOOL uploadOK = ([types containsObject:NSPasteboardTypeFileURL] && dropScpPath);

    // It's ok to paste if the the drag object is either a file or a string.
    BOOL pasteOK = !![[sender draggingPasteboard] availableTypeFromArray:@[ NSPasteboardTypeFileURL, NSPasteboardTypeString ]];

    const BOOL optionPressed = ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
    NSDragOperation sourceMask = [sender draggingSourceOperationMask];
    DLog(@"source mask=%@, optionPressed=%@, pasteOk=%@", @(sourceMask), @(optionPressed), @(pasteOK));
    if (!optionPressed && pasteOK && (sourceMask & (NSDragOperationGeneric | NSDragOperationCopy | NSDragOperationLink)) != 0) {
        DLog(@"Allowing a filename drag");
        // No modifier key was pressed and pasting is OK, so select the paste operation.
        NSArray *filenames = [pb filenamesOnPasteboardWithShellEscaping:YES forPaste:YES];
        DLog(@"filenames=%@", filenames);
        if (numberOfValidItemsPtr) {
            if (filenames.count) {
                *numberOfValidItemsPtr = filenames.count;
            } else {
                *numberOfValidItemsPtr = 1;
            }
        }
        if (sourceMask & NSDragOperationGeneric) {
            // This is preferred since it doesn't have the green plus indicating a copy
            return NSDragOperationGeneric;
        } else if (sourceMask & NSDragOperationLink) {
            // This fixes dragging from Fork, issue 10538. Apple doesn't deign to
            // describe the purpose of NSDragOperationLink so I'll assume this isn't a crime.
            return NSDragOperationLink;
        } else {
            // Even if the source only allows copy, we allow it. See issue 4286.
            // Such sources are silly and we route around the damage.
            return NSDragOperationCopy;
        }
    } else if (optionPressed && uploadOK && (sourceMask & NSDragOperationCopy) != 0) {
        DLog(@"Allowing an upload drag");
        // Either Option was pressed or the sender allows Copy but not Generic,
        // and it's ok to upload, so select the upload operation.
        if (numberOfValidItemsPtr) {
            *numberOfValidItemsPtr = [[pb filenamesOnPasteboardWithShellEscaping:NO forPaste:YES] count];
        }
        // You have to press option to get here so Copy is the only possibility.
        return NSDragOperationCopy;
    } else {
        // No luck.
        DLog(@"Not allowing drag");
        return NSDragOperationNone;
    }
}

- (void)_dragImage:(id<iTermImageInfoReading>)imageInfo forEvent:(NSEvent *)theEvent {
    NSImage *icon = [imageInfo imageWithCellSize:NSMakeSize(_charWidth, _lineHeight)
                                           scale:1];

    NSData *imageData = imageInfo.data;
    if (!imageData || !icon) {
        return;
    }

    // tell our app not switch windows (currently not working)
    [NSApp preventWindowOrdering];

    // drag from center of the image
    NSPoint dragPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];

    VT100GridCoord coord = VT100GridCoordMake((dragPoint.x - [iTermPreferences intForKey:kPreferenceKeySideMargins]) / _charWidth,
                                              dragPoint.y / _lineHeight);
    const screen_char_t* theLine = [_dataSource screenCharArrayForLine:coord.y].line;
    if (theLine &&
        coord.x < [_dataSource width] &&
        theLine[coord.x].image &&
        !theLine[coord.x].virtualPlaceholder &&
        theLine[coord.x].code == imageInfo.code) {
        // Get the cell you clicked on (small y at top of view)
        VT100GridCoord pos = GetPositionOfImageInChar(theLine[coord.x]);

        // Get the top-left origin of the image in cell coords
        VT100GridCoord imageCellOrigin = VT100GridCoordMake(coord.x - pos.x,
                                                            coord.y - pos.y);

        // Compute the pixel coordinate of the image's top left point
        NSPoint imageTopLeftPoint = NSMakePoint(imageCellOrigin.x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins],
                                                imageCellOrigin.y * _lineHeight);

        // Compute the distance from the click location to the image's origin
        NSPoint offset = NSMakePoint(dragPoint.x - imageTopLeftPoint.x,
                                     dragPoint.y - imageTopLeftPoint.y);

        // Adjust the drag point so the image won't jump as soon as the drag begins.
        dragPoint.x -= offset.x;
        dragPoint.y -= offset.y;
    }

    // start the drag
    NSPasteboardItem *pbItem = [imageInfo pasteboardItem];
    NSDraggingItem *dragItem = [[[NSDraggingItem alloc] initWithPasteboardWriter:pbItem] autorelease];
    [dragItem setDraggingFrame:NSMakeRect(dragPoint.x, dragPoint.y, icon.size.width, icon.size.height)
                      contents:icon];
    NSDraggingSession *draggingSession = [self beginDraggingSessionWithItems:@[ dragItem ]
                                                                       event:theEvent
                                                                      source:self];

    draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;
    draggingSession.draggingFormation = NSDraggingFormationNone;
}

- (void)_dragText:(NSString *)aString forEvent:(NSEvent *)theEvent {
    NSImage *anImage;
    int length;
    NSString *tmpString;
    NSSize imageSize;
    NSPoint dragPoint;

    length = [aString length];
    if ([aString length] > 15) {
        length = 15;
    }

    imageSize = NSMakeSize(_charWidth * length, _lineHeight);
    anImage = [[[NSImage alloc] initWithSize:imageSize] autorelease];
    [anImage lockFocus];
    if ([aString length] > 15) {
        tmpString = [NSString stringWithFormat:@"%@…",
                        [aString substringWithRange:NSMakeRange(0, 12)]];
    } else {
        tmpString = [aString substringWithRange:NSMakeRange(0, length)];
    }

    [tmpString drawInRect:NSMakeRect(0, 0, _charWidth * length, _lineHeight) withAttributes:nil];
    [anImage unlockFocus];

    // tell our app not switch windows (currently not working)
    [NSApp preventWindowOrdering];

    // drag from center of the image
    dragPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    dragPoint.x -= imageSize.width / 2;

    // start the drag
    NSPasteboardItem *pbItem = [[[NSPasteboardItem alloc] init] autorelease];
    [pbItem setString:aString forType:UTTypeUTF8PlainText.identifier];
    NSDraggingItem *dragItem =
        [[[NSDraggingItem alloc] initWithPasteboardWriter:pbItem] autorelease];
    [dragItem setDraggingFrame:NSMakeRect(dragPoint.x,
                                          dragPoint.y,
                                          anImage.size.width,
                                          anImage.size.height)
                      contents:anImage];
    NSDraggingSession *draggingSession = [self beginDraggingSessionWithItems:@[ dragItem ]
                                                                       event:theEvent
                                                                      source:self];

    draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;
    draggingSession.draggingFormation = NSDraggingFormationNone;
}

- (NSDragOperation)dragOperationForSender:(id<NSDraggingInfo>)sender {
    return [self dragOperationForSender:sender numberOfValidItems:NULL];
}

#pragma mark NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationEvery;
}

#pragma mark - File Transfer

- (BOOL)confirmUploadOfFiles:(NSArray *)files toPath:(SCPPath *)path {
    const BOOL useSSHIntegration = [_delegate textViewCanUploadOverSSHIntegrationTo:path];
    NSString *text;
    if (files.count == 0) {
        return NO;
    }
    if (files.count == 1) {
        text = [NSString stringWithFormat:@"OK to %@\n%@\nto\n%@@%@:%@?",
                useSSHIntegration ? @"copy" : @"scp",
                [files componentsJoinedByString:@", "],
                path.username, path.hostname, path.path];
    } else {
        text = [NSString stringWithFormat:@"OK to %@ the following files:\n%@\n\nto\n%@@%@:%@?",
                useSSHIntegration ? @"copy" : @"scp",
                [files componentsJoinedByString:@", "],
                path.username, path.hostname, path.path];
    }
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = text;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert layout];
    NSInteger button = [alert runModal];
    return (button == NSAlertFirstButtonReturn);
}

- (void)maybeUpload:(NSArray *)tuple {
    NSArray *propertyList = tuple[0];
    SCPPath *dropScpPath = tuple[1];
    DLog(@"Confirm upload to %@", dropScpPath);
    if ([self confirmUploadOfFiles:propertyList toPath:dropScpPath]) {
        DLog(@"initiating upload");
        [self.delegate uploadFiles:propertyList toPath:dropScpPath];
    }
}

- (BOOL)uploadFilenamesOnPasteboard:(NSPasteboard *)pasteboard location:(NSPoint)windowDropPoint {
    // Upload a file.
    NSArray *types = [pasteboard types];
    NSPoint dropPoint = [self convertPoint:windowDropPoint fromView:nil];
    int dropLine = dropPoint.y / _lineHeight;
    SCPPath *dropScpPath = [_dataSource scpPathForFile:@"" onLine:dropLine];
    NSArray *filenames = [pasteboard filenamesOnPasteboardWithShellEscaping:NO forPaste:NO];
    if ([types containsObject:NSPasteboardTypeFileURL] && filenames.count && dropScpPath) {
        // This is all so the mouse cursor will change to a plain arrow instead of the
        // drop target cursor.
        if (![[self window] isKindOfClass:[NSPanel class]]) {
            // Can't do this to a floating panel or we switch away from the lion fullscreen app we're over.
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        }
        [[self window] makeKeyAndOrderFront:nil];
        [self performSelector:@selector(maybeUpload:)
                   withObject:@[ filenames, dropScpPath ]
                   afterDelay:0];
        return YES;
    }
    return NO;
}

//
// Called when the dragged item is released in our drop area.
//
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    _drawingHelper.showDropTargets = NO;
    [self.delegate textViewDidUpdateDropTargetVisibility];
    NSPasteboard *draggingPasteboard = [sender draggingPasteboard];
    NSDragOperation dragOperation = [sender draggingSourceOperationMask];
    DLog(@"Perform drag operation");
    if (dragOperation & (NSDragOperationCopy | NSDragOperationGeneric | NSDragOperationLink)) {
        DLog(@"Drag operation is acceptable");
        if ([NSEvent modifierFlags] & NSEventModifierFlagOption) {
            DLog(@"Holding option so doing an upload");
            NSPoint windowDropPoint = [sender draggingLocation];
            return [self uploadFilenamesOnPasteboard:draggingPasteboard location:windowDropPoint];
        } else {
            DLog(@"No option so pasting filename");
            return [self pasteValuesOnPasteboard:draggingPasteboard
                                   cdToDirectory:(dragOperation == NSDragOperationGeneric)];
        }
    }
    DLog(@"Drag/drop Failing");
    return NO;
}

#pragma mark - Printing

- (void)print:(id)sender {
    NSRect visibleRect;
    int lineOffset, numLines;
    int type = sender ? [sender tag] : 0;
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];

    switch (type) {
        case 0: // visible range
            visibleRect = [[self enclosingScrollView] documentVisibleRect];
            // Starting from which line?
            lineOffset = visibleRect.origin.y / _lineHeight;
            // How many lines do we need to draw?
            numLines = visibleRect.size.height / _lineHeight;
            VT100GridCoordRange coordRange = VT100GridCoordRangeMake(0,
                                                                     lineOffset,
                                                                     [_dataSource width],
                                                                     lineOffset + numLines - 1);
            [self printContent:[extractor contentInRange:VT100GridWindowedRangeMake(coordRange, 0, 0)
                                       attributeProvider:^NSDictionary *(screen_char_t theChar, iTermExternalAttribute *ea) {
                return [self charAttributes:theChar externalAttributes:ea processed:NO elideDefaultBackgroundColor:NO];
            }
                                              nullPolicy:kiTermTextExtractorNullPolicyTreatAsSpace
                                                     pad:NO
                                      includeLastNewline:YES
                                  trimTrailingWhitespace:NO
                                            cappedAtSize:-1
                                            truncateTail:YES
                                       continuationChars:nil
                                                  coords:nil]];
            break;
        case 1: // text selection
            [self printContent:[self selectedAttributedTextWithPad:NO]];
            break;
        case 2: // entire buffer
            [self printContent:[self attributedContent]];
            break;
    }
}

- (void)printContent:(id)content {
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    [printInfo setHorizontalPagination:NSPrintingPaginationModeFit];
    [printInfo setVerticalPagination:NSPrintingPaginationModeAutomatic];
    [printInfo setVerticallyCentered:NO];

    // Create a temporary view with the contents, change to black on white, and
    // print it.
    NSRect frame = [[self enclosingScrollView] documentVisibleRect];
    NSTextView *tempView =
        [[[NSTextView alloc] initWithFrame:frame] autorelease];

    iTermPrintAccessoryViewController *accessory = nil;
    NSAttributedString *attributedString;
    if ([content isKindOfClass:[NSAttributedString class]]) {
        attributedString = content;
        accessory = [[[iTermPrintAccessoryViewController alloc] initWithNibName:@"iTermPrintAccessoryViewController"
                                                                         bundle:[NSBundle bundleForClass:self.class]] autorelease];
        accessory.userDidChangeSetting = ^() {
            NSAttributedString *theAttributedString = nil;
            if (accessory.blackAndWhite) {
                theAttributedString = [attributedString attributedStringByRemovingColor];
            } else {
                theAttributedString = attributedString;
            }
            [[tempView textStorage] setAttributedString:theAttributedString];
        };
    } else {
        NSDictionary *attributes =
            @{ NSBackgroundColorAttributeName: [NSColor textBackgroundColor],
               NSForegroundColorAttributeName: [NSColor textColor],
               NSFontAttributeName: _fontTable.asciiFont.font ?: [NSFont userFixedPitchFontOfSize:0] };
        attributedString = [[[NSAttributedString alloc] initWithString:content
                                                            attributes:attributes] autorelease];
    }
    [[tempView textStorage] setAttributedString:attributedString];

    // Now print the temporary view.
    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:tempView printInfo:printInfo];
    if (accessory) {
        operation.printPanel.options = (NSPrintPanelShowsCopies |
                                        NSPrintPanelShowsPaperSize |
                                        NSPrintPanelShowsOrientation |
                                        NSPrintPanelShowsScaling |
                                        NSPrintPanelShowsPreview);
        [operation.printPanel addAccessoryController:accessory];
    }
    [operation runOperation];
}

#pragma mark - NSTextInputClient

- (void)doCommandBySelector:(SEL)aSelector {
    [_keyboardHandler doCommandBySelector:aSelector];
}

- (void)insertText:(id)aString replacementRange:(NSRange)replacementRange {
    [_keyboardHandler insertText:aString replacementRange:replacementRange];
}

// Legacy NSTextInput method, probably not used by the system but used internally.
- (void)insertText:(id)aString {
    // TODO: The replacement range is wrong
    [self insertText:aString replacementRange:NSMakeRange(0, [_drawingHelper.markedText length])];
}

// TODO: Respect replacementRange
- (void)setMarkedText:(id)aString
        selectedRange:(NSRange)selRange
     replacementRange:(NSRange)replacementRange {
    DLog(@"setMarkedText%@ selectedRange%@ replacementRange:%@",
         aString, NSStringFromRange(selRange), NSStringFromRange(replacementRange));
    if ([aString isKindOfClass:[NSAttributedString class]]) {
        _drawingHelper.markedText = [[[NSAttributedString alloc] initWithString:[aString string]
                                                                     attributes:[self markedTextAttributes]] autorelease];
    } else {
        _drawingHelper.markedText = [[[NSAttributedString alloc] initWithString:aString
                                                                     attributes:[self markedTextAttributes]] autorelease];
    }
    _drawingHelper.inputMethodMarkedRange = NSMakeRange(0, [_drawingHelper.markedText length]);
    _drawingHelper.inputMethodSelectedRange = selRange;

    // Compute the proper imeOffset.
    int dirtStart;
    int dirtEnd;
    int dirtMax; 
    _drawingHelper.numberOfIMELines = 0;
    do {
        dirtStart = ([_dataSource cursorY] - 1 - _drawingHelper.numberOfIMELines) * [_dataSource width] + [_dataSource cursorX] - 1;
        dirtEnd = dirtStart + [self inputMethodEditorLength];
        dirtMax = [_dataSource height] * [_dataSource width];
        if (dirtEnd > dirtMax) {
            _drawingHelper.numberOfIMELines = _drawingHelper.numberOfIMELines + 1;
        }
    } while (dirtEnd > dirtMax);

    if (![_drawingHelper.markedText length]) {
        // The call to refresh won't invalidate the IME rect because
        // there is no IME any more. If the user backspaced over the only
        // char in the IME buffer then this causes it be erased.
        [self invalidateInputMethodEditorRect];
    }
    [_delegate refresh];
    [self scrollEnd];
}

- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange {
    [self setMarkedText:aString selectedRange:selRange replacementRange:NSMakeRange(0, 0)];
}

- (void)unmarkText {
    DLog(@"unmarkText");
    // As far as I can tell this is never called.
    _drawingHelper.inputMethodMarkedRange = NSMakeRange(0, 0);
    _drawingHelper.numberOfIMELines = 0;
    [self invalidateInputMethodEditorRect];
    [_delegate refresh];
    [self scrollEnd];
}

- (BOOL)hasMarkedText {
    return [_keyboardHandler hasMarkedText];
}

- (NSRange)markedRange {
    NSRange range;
    if (_drawingHelper.inputMethodMarkedRange.length > 0) {
        range = NSMakeRange([_dataSource cursorX]-1, _drawingHelper.inputMethodMarkedRange.length);
    } else {
        range = NSMakeRange([_dataSource cursorX]-1, 0);
    }
    DLog(@"markedRange->%@", NSStringFromRange(range));
    return range;
}

- (NSRange)selectedRange {
    DLog(@"selectedRange");
    if (_selection.hasSelection) {
        DLog(@"Use range of selection");
        return [self nsRangeForAbsCoordRange:_selection.allSubSelections.lastObject.absRange.coordRange];
    }
    DLog(@"Use range of cursor");
    return [self nsrangeOfCursor];
}

- (NSRange)nsrangeOfCursor {
    const int y = [_dataSource cursorY] - 1;
    const int x = [_dataSource cursorX] - 1;
    const long long offset = _dataSource.totalScrollbackOverflow + _dataSource.numberOfScrollbackLines;
    VT100GridAbsCoordRange range = VT100GridAbsCoordRangeMake(x,
                                                              offset + y,
                                                              x,
                                                              offset + y);
    return [self nsRangeForAbsCoordRange:range];
}

- (NSRange)nsRangeForAbsCoordRange:(VT100GridAbsCoordRange)range {
    DLog(@"%@", VT100GridAbsCoordRangeDescription(range));
    const long long width = _dataSource.width;
    return NSMakeRange(range.start.x + range.start.y * width,
                       VT100GridAbsCoordDistance(range.start, range.end, width));
}

- (NSArray *)validAttributesForMarkedText {
    return @[ NSForegroundColorAttributeName,
              NSBackgroundColorAttributeName,
              NSUnderlineStyleAttributeName,
              NSFontAttributeName ];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange {
    return [self attributedSubstringForProposedRange:theRange actualRange:NULL];
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)proposedRange
                                                actualRange:(NSRangePointer)actualRange {
    DLog(@"attributedSubstringForProposedRange:%@", NSStringFromRange(proposedRange));
    NSRange aRange = NSIntersectionRange(proposedRange,
                                         NSMakeRange(0, _drawingHelper.markedText.length));
    if (proposedRange.length > 0 && aRange.length == 0) {
        aRange.location = NSNotFound;
    }
    if (actualRange) {
        *actualRange = aRange;
    }
    if (aRange.location == NSNotFound) {
        return nil;
    }
    return [_drawingHelper.markedText attributedSubstringFromRange:NSMakeRange(0, aRange.length)];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)thePoint {
    return MAX(0, thePoint.x / _charWidth);
}

- (long)conversationIdentifier {
    return (long)self; // not sure about this
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange actualRange:(NSRangePointer)actualRange {
    int y = [_dataSource cursorY] - 1;
    int x = [_dataSource cursorX] - 1;

    NSRect rect=NSMakeRect(x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins],
                           (y + [_dataSource numberOfLines] - [_dataSource height] + 1) * _lineHeight,
                           _charWidth * theRange.length,
                           _lineHeight);
    rect.origin = [[self window] pointToScreenCoords:[self convertPoint:rect.origin toView:nil]];
    if (actualRange) {
        *actualRange = theRange;
    }

    return rect;
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange {
    return [self firstRectForCharacterRange:theRange actualRange:NULL];
}

#pragma mark - Find on page

- (IBAction)performFindPanelAction:(id)sender {
    NSMenuItem *menuItem = [NSMenuItem castFrom:sender];
    if (!menuItem) {
        return;
    }
    switch ((NSFindPanelAction)menuItem.tag) {
        case NSFindPanelActionShowFindPanel:
            [self.delegate textViewShowFindPanel];
            return;

        case NSFindPanelActionSelectAll:
            [self convertMatchesToSelections];
            return;

        case NSFindPanelActionNext:
        case NSFindPanelActionReplace:
        case NSFindPanelActionPrevious:
        case NSFindPanelActionReplaceAll:
        case NSFindPanelActionReplaceAndFind:
        case NSFindPanelActionSelectAllInSelection:
        case NSFindPanelActionReplaceAllInSelection:
            // For now we use a nonstandard way of doing these things for no good reason.
            // This will be fixed over time.
            return;
        case NSFindPanelActionSetFindString: {
            NSString *selectedText = [self selectedTextWithTrailingWhitespace];
            switch ([iTermFindDriver mode]) {
                case iTermFindModeSmartCaseSensitivity:
                case iTermFindModeCaseSensitiveSubstring:
                case iTermFindModeCaseInsensitiveSubstring:
                    break;
                case iTermFindModeCaseSensitiveRegex:
                case iTermFindModeCaseInsensitiveRegex:
                    selectedText = [selectedText stringByEscapingForRegex];
                    break;

            }
            if (selectedText) {
                [[iTermFindPasteboard sharedInstance] setStringValueUnconditionally:selectedText];
                [[iTermFindPasteboard sharedInstance] updateObservers:_delegate internallyGenerated:YES];
            }
            break;
        }
    }
}

- (BOOL)findInProgress {
    return _findOnPageHelper.findInProgress;
}

- (void)removeSearchResultsInRange:(VT100GridAbsCoordRange)range {
    [_findOnPageHelper removeSearchResultsInRange:NSMakeRange(range.start.y, range.end.y - range.start.y)];
}

- (void)addSearchResult:(SearchResult *)searchResult {
    [_findOnPageHelper addSearchResult:searchResult width:[_dataSource width]];
}

- (BOOL)continueFind:(double *)progress range:(NSRange *)rangePtr {
    return [_findOnPageHelper continueFind:progress
                                  rangeOut:rangePtr
                                     width:[_dataSource width]
                             numberOfLines:[_dataSource numberOfLines]
                        overflowAdjustment:[_dataSource totalScrollbackOverflow] - [_dataSource scrollbackOverflow]];
}

- (void)findOnPageHelperSearchExternallyFor:(NSString *)query mode:(iTermFindMode)mode {
    [_findOnPageHelper addExternalResults:[self searchPortholesFor:query mode:mode]
                                    width:self.dataSource.width ?: 1];
}

- (void)findOnPageHelperRequestRedraw {
    [self requestDelegateRedraw];
}

- (void)findOnPageHelperRemoveExternalHighlights {
    [self removePortholeHighlights];
}

- (void)findOnPageHelperRemoveExternalHighlightsFrom:(iTermExternalSearchResult *)externalSearchResult {
    [self removePortholeHighlightsFrom:externalSearchResult];
}

- (void)selectCoordRange:(VT100GridCoordRange)range {
    [_selection clearSelection];
    VT100GridAbsCoordRange absRange = VT100GridAbsCoordRangeFromCoordRange(range, _dataSource.totalScrollbackOverflow);
    iTermSubSelection *sub =
        [iTermSubSelection subSelectionWithAbsRange:VT100GridAbsWindowedRangeMake(absRange, 0, 0)
                                               mode:kiTermSelectionModeCharacter
                                              width:_dataSource.width];
    [_selection addSubSelection:sub];
    [_delegate textViewDidSelectRangeForFindOnPage:range];
}

- (void)selectAbsWindowedCoordRange:(VT100GridAbsWindowedRange)windowedRange {
    [_selection clearSelection];
    iTermSubSelection *sub =
        [iTermSubSelection subSelectionWithAbsRange:windowedRange
                                               mode:kiTermSelectionModeCharacter
                                              width:_dataSource.width];
    [_selection addSubSelection:sub];
    [_delegate textViewDidSelectRangeForFindOnPage:VT100GridWindowedRangeFromVT100GridAbsWindowedRange(windowedRange, self.dataSource.totalScrollbackOverflow).coordRange];
}

- (NSRect)frameForCoord:(VT100GridCoord)coord {
    return NSMakeRect(MAX(0, floor(coord.x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins])),
                      MAX(0, coord.y * _lineHeight),
                      _charWidth,
                      _lineHeight);
}

- (iTermTextExtractor *)bidiExtractor {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    extractor.supportBidi = [iTermPreferences boolForKey:kPreferenceKeyBidi];
    return extractor;
}

- (void)findOnPageSelectRange:(VT100GridCoordRange)logicalRange wrapped:(BOOL)wrapped {
    VT100GridCoordRange range = [self.bidiExtractor visualRangeForLogical:logicalRange];
    [self selectCoordRange:range];
    VT100GridAbsCoordRange absRange = VT100GridAbsCoordRangeFromCoordRange(range, _dataSource.totalScrollbackOverflow);
    // Let the scrollview scroll if needs to before showing the find indicator.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showFindIndicator:absRange];
    });
    if (!wrapped) {
        [self requestDelegateRedraw];
    }
}

- (void)showFindIndicator:(VT100GridAbsCoordRange)absRange {
    VT100GridCoordRange range = VT100GridCoordRangeFromAbsCoordRange(absRange, _dataSource.totalScrollbackOverflow);
    [self.delegate textViewShowFindIndicator:range];
}

- (VT100GridCoordRange)findOnPageSelectExternalResult:(iTermExternalSearchResult *)result {
    return [self selectExternalSearchResult:result multiple:NO scroll:YES];
}

- (void)findOnPageDidWrapForwards:(BOOL)directionIsForwards {
    if (directionIsForwards) {
        [self beginFlash:kiTermIndicatorWrapToTop];
    } else {
        [self beginFlash:kiTermIndicatorWrapToBottom];
    }
}

- (void)findOnPageRevealRange:(VT100GridCoordRange)range {
    const VT100GridRange visibleLines = [self rangeOfVisibleLines];
    const VT100GridCoordRange visibleRange = VT100GridCoordRangeMake(0,
                                                                     visibleLines.location,
                                                                     _dataSource.width,
                                                                     VT100GridRangeMax(visibleLines));
    if (VT100GridCoordRangeContainsCoord(visibleRange, range.start) &&
        VT100GridCoordRangeContainsCoord(visibleRange, range.end)) {
        DLog(@"Entire range %@ is visible within %@ so don't scroll",
             VT100GridCoordRangeDescription(range),
             VT100GridCoordRangeDescription(visibleRange));
        [self requestDelegateRedraw];
        return;
    }
    // Lock scrolling after finding text
    [self cancelMomentumScroll];
    [self lockScroll];

    [self scrollToCenterLine:range.end.y];
    [self requestDelegateRedraw];
}

- (void)findOnPageFailed {
    [_selection clearSelection];
    [self requestDelegateRedraw];
}

- (long long)findOnPageOverflowAdjustment {
    return [_dataSource totalScrollbackOverflow] - [_dataSource scrollbackOverflow];
}

- (void)resetFindCursor {
    [_findOnPageHelper resetFindCursor];
}

- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset
scrollToFirstResult:(BOOL)scrollToFirstResult
             force:(BOOL)force {
    DLog(@"begin self=%@ aString=%@", self, aString);
    [_findOnPageHelper findString:aString
                 forwardDirection:direction
                             mode:mode
                       withOffset:offset
                     searchEngine:_dataSource.searchEngine
                    numberOfLines:_dataSource.numberOfLines
          totalScrollbackOverflow:_dataSource.totalScrollbackOverflow
              scrollToFirstResult:scrollToFirstResult
                            force:force];
}

- (void)clearHighlights:(BOOL)resetContext {
    DLog(@"begin");
    [_findOnPageHelper clearHighlights];
    if (resetContext) {
        [_findOnPageHelper resetSearchEngine];
    } else {
        [_findOnPageHelper removeAllSearchResults];
    }
}

- (NSRange)findOnPageRangeOfVisibleLines {
    return NSMakeRange(_dataSource.totalScrollbackOverflow, _dataSource.numberOfLines);
}

- (void)findOnPageLocationsDidChange {
    [_delegate textViewFindOnPageLocationsDidChange];
}

- (void)findOnPageSelectedResultDidChange {
    [_delegate textViewFindOnPageSelectedResultDidChange];
}

#pragma mark - Services

- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType {
    NSSet *acceptedReturnTypes = [NSSet setWithArray:@[ UTTypeUTF8PlainText.identifier,
                                                        NSPasteboardTypeString ]];
    NSSet *acceptedSendTypes = nil;
    if ([_selection hasSelection] && [_selection length] <= [_dataSource width] * 10000) {
        acceptedSendTypes = acceptedReturnTypes;
    }
    if ((sendType == nil || [acceptedSendTypes containsObject:sendType]) &&
        (returnType == nil || [acceptedReturnTypes containsObject:returnType])) {
        return self;
    } else {
        return nil;
    }
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types {
    // It is agonizingly slow to copy hundreds of thousands of lines just because the context
    // menu is opening. Services use this to get access to the clipboard contents but
    // it's lousy to hang for a few minutes for a feature that won't be used very much, esp. for
    // such large selections. In OS 10.9 this is called when opening the context menu, even though
    // it is deprecated by 10.9.
    NSString *copyString =
        [self selectedTextCappedAtSize:[iTermAdvancedSettingsModel maximumBytesToProvideToServices]];

    if (copyString && [copyString length] > 0) {
        [pboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
        [pboard setString:copyString forType:NSPasteboardTypeString];
        return YES;
    }

    return NO;
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard {
    NSString *string = [pboard stringForType:NSPasteboardTypeString];
    if (string.length) {
        [_delegate insertText:string];
        return YES;
    } else {
        return NO;
    }
}

#pragma mark - Miscellaneous APIs

// This textview is about to be hidden behind another tab.
- (void)aboutToHide {
    [_selectionScrollHelper mouseUp];
}

#pragma mark - Find Cursor

- (NSRect)rectForCoord:(VT100GridCoord)coord {
    return NSMakeRect([iTermPreferences intForKey:kPreferenceKeySideMargins] + coord.x * _charWidth,
                      coord.y * _lineHeight,
                      _charWidth,
                      _lineHeight);
}

- (NSRect)rectForGridCoord:(VT100GridCoord)coord {
    const int firstGridLine = [_dataSource numberOfLines] - [_dataSource height];
    return [self rectForCoord:VT100GridCoordMake(coord.x, firstGridLine + coord.y)];
}

- (NSRect)cursorFrame {
    return [self rectForGridCoord:VT100GridCoordMake(_dataSource.cursorX - 1,
                                                     _dataSource.cursorY - 1)];
}

- (CGFloat)verticalOffset {
    return self.frame.size.height - NSMaxY(self.enclosingScrollView.documentVisibleRect);
}

- (NSPoint)cursorCenterInScreenCoords {
    NSPoint cursorCenter;
    if ([self hasMarkedText]) {
        cursorCenter = _drawingHelper.imeCursorLastPos;
    } else {
        cursorCenter = [self cursorFrame].origin;
    }
    cursorCenter.x += _charWidth / 2;
    cursorCenter.y += _lineHeight / 2;
    NSPoint cursorCenterInWindowCoords = [self convertPoint:cursorCenter toView:nil];
    return  [[self window] pointToScreenCoords:cursorCenterInWindowCoords];
}

// Returns the location of the cursor relative to the origin of self.findCursorWindow.
- (NSPoint)cursorCenterInFindCursorWindowCoords {
    NSPoint centerInScreenCoords = [self cursorCenterInScreenCoords];
    return [_findCursorWindow pointFromScreenCoords:centerInScreenCoords];
}

// Returns the proper frame for self.findCursorWindow, including every screen that the
// "hole" will be in.
- (NSRect)cursorScreenFrame {
    NSRect frame = NSZeroRect;
    for (NSScreen *aScreen in [NSScreen screens]) {
        NSRect screenFrame = [aScreen frame];
        if (NSIntersectsRect([[self window] frame], screenFrame)) {
            frame = NSUnionRect(frame, screenFrame);
        }
    }
    if (NSEqualRects(frame, NSZeroRect)) {
        frame = [[self window] frame];
    }
    return frame;
}

- (void)createFindCursorWindowWithFireworks:(BOOL)forceFireworks {
    [self scrollRectToVisible:[self cursorFrame]];
    self.findCursorWindow = [[[NSWindow alloc] initWithContentRect:NSZeroRect
                                                         styleMask:NSWindowStyleMaskBorderless
                                                           backing:NSBackingStoreBuffered
                                                             defer:YES] autorelease];
    [_findCursorWindow setLevel:NSFloatingWindowLevel];
    NSRect screenFrame = [self cursorScreenFrame];
    [_findCursorWindow setFrame:screenFrame display:YES];
    _findCursorWindow.backgroundColor = [NSColor clearColor];
    _findCursorWindow.opaque = NO;
    [_findCursorWindow makeKeyAndOrderFront:nil];

    if (forceFireworks) {
        self.findCursorView = [iTermFindCursorView newFireworksViewWithFrame:NSMakeRect(0,
                                                                                        0,
                                                                                        screenFrame.size.width,
                                                                                        screenFrame.size.height)];
    } else {
        self.findCursorView = [[iTermFindCursorView alloc] initWithFrame:NSMakeRect(0,
                                                                                    0,
                                                                                    screenFrame.size.width,
                                                                                    screenFrame.size.height)];
    }
    _findCursorView.delegate = self;
    NSPoint p = [self cursorCenterInFindCursorWindowCoords];
    _findCursorView.cursorPosition = p;
    [_findCursorWindow setContentView:_findCursorView];
}

- (void)beginFindCursor:(BOOL)hold {
    [self beginFindCursor:hold forceFireworks:NO];
}

- (void)beginFindCursor:(BOOL)hold forceFireworks:(BOOL)forceFireworks {
    _cursorVisible = YES;
    [self requestDelegateRedraw];
    if (!_findCursorView) {
        [self createFindCursorWindowWithFireworks:forceFireworks];
    }
    if (hold) {
        [_findCursorView startTearDownTimer];
    } else {
        [_findCursorView stopTearDownTimer];
    }
    _findCursorView.autohide = NO;
}

- (void)placeFindCursorOnAutoHide {
    _findCursorView.autohide = YES;
}

- (BOOL)isFindingCursor {
    return _findCursorView != nil;
}

- (void)findCursorViewDismiss {
    [self endFindCursor];
}

- (void)endFindCursor {
    [NSAnimationContext beginGrouping];
    NSWindow *theWindow = [_findCursorWindow retain];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [theWindow close];  // This sends release to the window
    }];
    [[_findCursorWindow animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];

    [_findCursorView stopTearDownTimer];
    self.findCursorWindow = nil;
    _findCursorView.stopping = YES;
    self.findCursorView = nil;
}

- (void)setFindCursorView:(iTermFindCursorView *)view {
    [_findCursorView autorelease];
    _findCursorView = [view retain];
}

- (void)showFireworks {
    [self beginFindCursor:YES forceFireworks:YES];
    [self placeFindCursorOnAutoHide];
}

#pragma mark - Semantic History Delegate

- (void)semanticHistoryLaunchCoprocessWithCommand:(NSString *)command {
    [_delegate launchCoprocessWithCommand:command];
}

- (void)semanticHistorySendText:(NSString *)text {
    [_delegate sendText:text escaping:iTermSendTextEscapingVim];
}

- (PTYFontInfo *)getFontForChar:(UniChar)ch
                      isComplex:(BOOL)isComplex
                     renderBold:(BOOL *)renderBold
                   renderItalic:(BOOL *)renderItalic
                       remapped:(UTF32Char *)remapped {
    return [_fontTable fontForCharacter:isComplex ? [CharToStr(ch, isComplex) longCharacterAtIndex:0] : ch
                            useBoldFont:_useBoldFont
                          useItalicFont:_useItalicFont
                             renderBold:renderBold
                           renderItalic:renderItalic
                               remapped:remapped];
}

#pragma mark - Miscellaneous Notifications

- (void)applicationDidResignActive:(NSNotification *)notification {
    DLog(@"applicationDidResignActive: reset _numTouches to 0");
    _mouseHandler.numTouches = 0;
}

- (void)redrawTerminalsNotification:(NSNotification *)notification {
    [self requestDelegateRedraw];
}

- (void)refreshTerminal:(NSNotification *)notification {
    [self requestDelegateRedraw];
}

#pragma mark - iTermSelectionDelegate

- (void)selectionDidChange:(iTermSelection *)selection {
    DLog(@"selectionDidChange to %@", selection);
    if (selection != _selection && selection != _oldSelection) {
        DLog(@"Not my selection. Ignore it.");
        return;
    }
    if (!_selection.live && selection.hasSelection) {
        iTermPromise<NSString *> *promise = [self recordSelection:selection];
        [promise onQueue:dispatch_get_main_queue() then:^(NSString * _Nonnull value) {
            DLog(@"Update scope variables for selection");
            [_delegate textViewSelectionDidChangeToTruncatedString:value];
        }];
    } else {
        [_delegate textViewSelectionDidChangeToTruncatedString:@""];
    }
    [self removePortholeSelections];
    [self requestDelegateRedraw];
    DLog(@"Selection did change: selection=%@. stack=%@",
         selection, [NSThread callStackSymbols]);
}

- (void)liveSelectionDidEnd {
    if ([self _haveShortSelection] && [iTermAdvancedSettingsModel autoSearch]) {
        NSString *selection = [self selectedText];
        if (selection) {
            [[iTermFindPasteboard sharedInstance] setStringValueUnconditionally:selection];
            [[iTermFindPasteboard sharedInstance] updateObservers:_delegate internallyGenerated:YES];
        }
    }
    [self.delegate textViewLiveSelectionDidEnd];
}

- (VT100GridRange)selectionRangeOfTerminalNullsOnAbsoluteLine:(long long)absLineNumber {
    const long long lineNumber = absLineNumber - _dataSource.totalScrollbackOverflow;
    if (lineNumber < 0 || lineNumber > INT_MAX) {
        return VT100GridRangeMake(0, 0);
    }
    if ([_dataSource bidiInfoForLine:lineNumber] != nil) {
        // TODO: This is a hack. A proper fix would give iTermSelection the ability to extend selection leftwards for lines that are right-justified.
        return VT100GridRangeMake(_dataSource.width, 0);
    }

    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    int length = [extractor lengthOfLine:lineNumber];
    int width = [_dataSource width];
    return VT100GridRangeMake(length, width - length);
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForParentheticalAt:(VT100GridAbsCoord)absCoord {
    BOOL ok;
    const VT100GridCoord coord = VT100GridCoordFromAbsCoord(absCoord, _dataSource.totalScrollbackOverflow, &ok);
    if (!ok) {
        const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, totalScrollbackOverflow, 0, totalScrollbackOverflow), 0, 0);
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    [extractor restrictToLogicalWindowIncludingCoord:coord];
    const VT100GridWindowedRange relative = [extractor rangeOfParentheticalSubstringAtLocation:coord];
    return VT100GridAbsWindowedRangeFromWindowedRange(relative, _dataSource.totalScrollbackOverflow);
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForWordAt:(VT100GridAbsCoord)absCoord {
    BOOL ok;
    const VT100GridCoord coord = VT100GridCoordFromAbsCoord(absCoord, _dataSource.totalScrollbackOverflow, &ok);
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    if (!ok) {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, totalScrollbackOverflow, 0, totalScrollbackOverflow), 0, 0);
    }
    VT100GridWindowedRange range;
    [self getWordForX:coord.x
                    y:coord.y
                range:&range
      respectDividers:[self liveSelectionRespectsSoftBoundaries]];
    return VT100GridAbsWindowedRangeFromWindowedRange(range, totalScrollbackOverflow);
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForSmartSelectionAt:(VT100GridAbsCoord)absCoord {
    VT100GridAbsWindowedRange absRange;
    [_urlActionHelper smartSelectAtAbsoluteCoord:absCoord
                                              to:&absRange
                                ignoringNewlines:NO
                                  actionRequired:NO
                                 respectDividers:[self liveSelectionRespectsSoftBoundaries]];
    return absRange;
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForWrappedLineAt:(VT100GridAbsCoord)absCoord {
    __block VT100GridWindowedRange relativeRange = { 0 };
    const BOOL ok =
    [self withRelativeCoord:absCoord block:^(VT100GridCoord coord) {
        iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
        if ([self liveSelectionRespectsSoftBoundaries]) {
            [extractor restrictToLogicalWindowIncludingCoord:coord];
        }
        relativeRange = [extractor rangeForWrappedLineEncompassing:coord
                                              respectContinuations:NO
                                                          maxChars:-1];
    }];
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    if (!ok) {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, totalScrollbackOverflow, 0, totalScrollbackOverflow), 0, 0);
    }
    return VT100GridAbsWindowedRangeFromWindowedRange(relativeRange, totalScrollbackOverflow);
}

- (int)selectionViewportWidth {
    return [_dataSource width];
}

- (VT100GridAbsWindowedRange)selectionAbsRangeForLineAt:(VT100GridAbsCoord)absCoord {
    __block VT100GridAbsWindowedRange result = { 0 };
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    const BOOL ok =
    [self withRelativeCoord:absCoord block:^(VT100GridCoord coord) {
        if (![self liveSelectionRespectsSoftBoundaries]) {
            result = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0,
                                                                              absCoord.y,
                                                                              [_dataSource width],
                                                                              absCoord.y),
                                                   0, 0);
            return;
        }
        iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
        [extractor restrictToLogicalWindowIncludingCoord:coord];
        result = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(extractor.logicalWindow.location,
                                                                          absCoord.y,
                                                                          VT100GridRangeMax(extractor.logicalWindow) + 1,
                                                                          absCoord.y),
                                          extractor.logicalWindow.location,
                                          extractor.logicalWindow.length);
    }];
    if (!ok) {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, totalScrollbackOverflow, 0, totalScrollbackOverflow), 0, 0);
    }
    return result;
}

- (VT100GridAbsCoord)selectionPredecessorOfAbsCoord:(VT100GridAbsCoord)absCoord {
    __block VT100GridAbsCoord result = { 0 };
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    const BOOL ok =
    [self withRelativeCoord:absCoord block:^(VT100GridCoord relativeCoord) {
        VT100GridCoord coord = relativeCoord;
        const screen_char_t *theLine;
        do {
            coord.x--;
            if (coord.x < 0) {
                coord.x = [_dataSource width] - 1;
                coord.y--;
                if (coord.y < 0) {
                    coord.x = coord.y = 0;
                    break;
                }
             }

            theLine = [_dataSource screenCharArrayForLine:coord.y].line;
        } while (ScreenCharIsDWC_RIGHT(theLine[coord.x]));
        result = VT100GridAbsCoordFromCoord(coord, totalScrollbackOverflow);
    }];
    if (!ok) {
        return VT100GridAbsCoordMake(0, totalScrollbackOverflow);
    }
    return result;
}

- (long long)selectionTotalScrollbackOverflow {
    return _dataSource.totalScrollbackOverflow;
}

- (NSIndexSet *)selectionIndexesOnAbsoluteLine:(long long)absLine
                           containingCharacter:(unichar)c
                                       inRange:(NSRange)range {
    const long long totalScrollbackOverflow = _dataSource.totalScrollbackOverflow;
    if (absLine < totalScrollbackOverflow || absLine - totalScrollbackOverflow > INT_MAX) {
        return nil;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    return [extractor indexesOnLine:absLine - totalScrollbackOverflow
                containingCharacter:c
                            inRange:range];
}

#pragma mark - iTermColorMapDelegate

- (void)immutableColorMap:(id<iTermColorMapReading>)colorMap didChangeColorForKey:(iTermColorMapKey)theKey from:(NSColor *)before to:(NSColor *)after {
    if (theKey == kColorMapBackground) {
        [self updateScrollerForBackgroundColor];
        [[self enclosingScrollView] setBackgroundColor:[colorMap colorForKey:theKey]];
        [self recomputeBadgeLabel];
        [_delegate textViewBackgroundColorDidChangeFrom:before to:after];
        [_delegate textViewProcessedBackgroundColorDidChange];
    } else if (theKey == kColorMapForeground) {
        [self recomputeBadgeLabel];
        [_delegate textViewForegroundColorDidChangeFrom:before to:after];
    } else if (theKey == kColorMapCursor) {
        [_delegate textViewCursorColorDidChangeFrom:before to:after];
    } else if (theKey == kColorMapSelection) {
        _drawingHelper.unfocusedSelectionColor = [[_colorMap colorForKey:theKey] colorDimmedBy:2.0/3.0
                                                                              towardsGrayLevel:0.5];
    }
    [self updatePortholeColorsWithUseSelectedTextColor:[_delegate textViewShouldUseSelectedTextColor]
                                           deferUpdate:YES];
    [self requestDelegateRedraw];
}

- (void)immutableColorMap:(id<iTermColorMapReading>)colorMap
    dimmingAmountDidChangeTo:(double)dimmingAmount {
    [_delegate textViewProcessedBackgroundColorDidChange];
    [self requestDelegateRedraw];
    [self setNeedsDisplay:YES];
}

- (void)immutableColorMap:(id<iTermColorMapReading>)colorMap
    mutingAmountDidChangeTo:(double)mutingAmount {
    [_delegate textViewProcessedBackgroundColorDidChange];
    [self requestDelegateRedraw];
    [self setNeedsDisplay:YES];
}

#pragma mark - iTermIndicatorsHelperDelegate

- (NSColor *)indicatorFullScreenFlashColor {
    return [self defaultTextColor];
}

- (void)indicatorNeedsDisplay {
    [self requestDelegateRedraw];
}

#pragma mark - Mouse reporting

- (NSRect)liveRect {
    int numLines = [_dataSource numberOfLines];
    NSRect rect;
    int height = [_dataSource height];
    rect.origin.y = numLines - height;
    rect.origin.y *= _lineHeight;
    rect.origin.x = [iTermPreferences intForKey:kPreferenceKeySideMargins];
    rect.size.width = _charWidth * [_dataSource width];
    rect.size.height = _lineHeight * [_dataSource height];
    return rect;
}

- (NSPoint)pointForEvent:(NSEvent *)event {
    return [self convertPoint:[event locationInWindow] fromView:nil];
}

#pragma mark - Selection Scroll

- (void)selectionScrollWillStart {
    PTYScroller *scroller = (PTYScroller *)self.enclosingScrollView.verticalScroller;
    scroller.userScroll = YES;
    [_mouseHandler selectionScrollWillStart];
}

#pragma mark - Color

- (NSColor*)colorForCode:(int)theIndex
                   green:(int)green
                    blue:(int)blue
               colorMode:(ColorMode)theMode
                    bold:(BOOL)isBold
                   faint:(BOOL)isFaint
            isBackground:(BOOL)isBackground {
    iTermColorMapKey key = [self colorMapKeyForCode:theIndex
                                              green:green
                                               blue:blue
                                          colorMode:theMode
                                               bold:isBold
                                       isBackground:isBackground];
    NSColor *color;
    iTermColorMap *colorMap = self.colorMap;
    if (isBackground) {
        color = [colorMap colorForKey:key];
    } else {
        color = [self.colorMap colorForKey:key];
        if (isFaint) {
            color = [color colorWithAlphaComponent:self.colorMap.faintTextAlpha];
        }
    }
    return color;
}

- (iTermColorMapKey)colorMapKeyForCode:(int)code
                                 green:(int)green
                                  blue:(int)blue
                             colorMode:(ColorMode)mode
                                  bold:(BOOL)isBold
                          isBackground:(BOOL)isBackground {
    return [_colorMap keyForColor:code
                            green:green
                             blue:blue
                        colorMode:mode
                             bold:isBold
                     isBackground:isBackground
               useCustomBoldColor:self.useCustomBoldColor
                     brightenBold:self.brightenBold];
}

#pragma mark - iTermTextDrawingHelperDelegate

- (void)drawingHelperDrawBackgroundImageInRect:(NSRect)rect
                        blendDefaultBackground:(BOOL)blend
                                 virtualOffset:(CGFloat)virtualOffset {
    [_delegate textViewDrawBackgroundImageInView:self
                                        viewRect:rect
                          blendDefaultBackground:blend
                                   virtualOffset:virtualOffset];
}

- (id<iTermMark>)drawingHelperMarkOnLine:(int)line {
    return [_dataSource drawableMarkOnLine:line];
}

- (const screen_char_t *)drawingHelperLineAtIndex:(int)line {
    return [_dataSource screenCharArrayForLine:line].line;
}

- (id<iTermExternalAttributeIndexReading>)drawingHelperExternalAttributesOnLine:(int)lineNumber {
    return [_dataSource externalAttributeIndexForLine:lineNumber];
}

- (iTermImmutableMetadata)drawingHelperMetadataOnLine:(int)lineNumber {
    return [_dataSource metadataOnLine:lineNumber];
}

- (const screen_char_t *)drawingHelperLineAtScreenIndex:(int)line {
    return [_dataSource screenCharArrayAtScreenIndex:line].line;
}

- (NSArray *)drawingHelperCharactersWithNotesOnLine:(int)line {
    return [_dataSource charactersWithNotesOnLine:line];
}

- (void)drawingHelperUpdateFindCursorView {
    if ([self isFindingCursor]) {
        NSPoint cp = [self cursorCenterInFindCursorWindowCoords];
        if (!NSEqualPoints(_findCursorView.cursorPosition, cp)) {
            _findCursorView.cursorPosition = cp;
            [_findCursorView setNeedsDisplay:YES];
        }
    }
}

- (NSDate *)drawingHelperTimestampForLine:(int)line {
    return [self.dataSource timestampForLine:line];
}

- (NSColor *)drawingHelperColorForCode:(int)theIndex
                                 green:(int)green
                                  blue:(int)blue
                             colorMode:(ColorMode)theMode
                                  bold:(BOOL)isBold
                                 faint:(BOOL)isFaint
                          isBackground:(BOOL)isBackground {
    return [self colorForCode:theIndex
                        green:green
                         blue:blue
                    colorMode:theMode
                         bold:isBold
                        faint:isFaint
                 isBackground:isBackground];
}

- (PTYFontInfo *)drawingHelperFontForChar:(UniChar)ch
                                isComplex:(BOOL)isComplex
                               renderBold:(BOOL *)renderBold
                             renderItalic:(BOOL *)renderItalic
                                 remapped:(UTF32Char *)remapped {
    return [self getFontForChar:ch
                      isComplex:isComplex
                     renderBold:renderBold
                   renderItalic:renderItalic
                       remapped:remapped];
}

- (NSData *)drawingHelperMatchesOnLine:(int)line {
    return _findOnPageHelper.highlightMap[@(line + _dataSource.totalScrollbackOverflow)];
}

- (void)drawingHelperDidFindRunOfAnimatedCellsStartingAt:(VT100GridCoord)coord
                                                ofLength:(int)length {
    [_dataSource setRangeOfCharsAnimated:NSMakeRange(coord.x, length) onLine:coord.y];
}

- (NSString *)drawingHelperLabelForDropTargetOnLine:(int)line {
    SCPPath *scpFile = [_dataSource scpPathForFile:@"" onLine:line];
    if (!scpFile) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@@%@:%@", scpFile.username, scpFile.hostname, scpFile.path];
}

- (BOOL)drawingHelperShouldPadBackgrounds:(out NSSize *)padding {
    return NO;
}

- (NSArray<iTermTerminalButton *> *)drawingHelperTerminalButtons  API_AVAILABLE(macos(11)){
    return [self terminalButtons];
}

- (iTermBidiDisplayInfo * _Nullable)drawingHelperBidiInfoForLine:(int)line {
    return [self.dataSource bidiInfoForLine:line];
}

- (VT100GridAbsCoord)absCoordForButton:(iTermTerminalButton *)button API_AVAILABLE(macos(11)) {
    if (!button.mark) {
        NSInteger y = button.transientAbsY;
        if (y >= 0) {
            // -1 means go in the right margin
            return VT100GridAbsCoordMake(-1, y);
        }
    }
    iTermTerminalMarkButton *markButton = [iTermTerminalMarkButton castFrom:button];
    id<iTermMark> mark = button.mark;
    if (markButton.shouldFloat) {
        const VT100GridAbsCoordRange markAbsCoordRange = [_delegate textViewCoordRangeForCommandAndOutputAtMark:mark];
        const NSRange markRange = NSMakeRange(markAbsCoordRange.start.y,
                                              markAbsCoordRange.end.y - markAbsCoordRange.start.y + 1);
        const NSRange visibleRange = [self visibleAbsoluteRangeIncludingOffscreenCommandLineIfVisible:NO];
        if (visibleRange.location == NSNotFound) {
            return VT100GridAbsCoordMake(-1, -1);
        }
        const NSRange intersectionRange = NSIntersectionRange(markRange, visibleRange);
        return VT100GridAbsCoordMake(self.dataSource.width + markButton.dx,
                                     intersectionRange.location);
    }
    Interval *interval = mark.entry.interval;
    if (!interval) {
        return VT100GridAbsCoordMake(-1, -1);
    }
    const VT100GridAbsCoord markCoord = [self.dataSource absCoordRangeForInterval:interval].start;
    if (markButton) {
        return VT100GridAbsCoordMake(self.dataSource.width + markButton.dx, markCoord.y - 1);
    }
    return markCoord;
}

// Does not include hover buttons.
- (NSArray<iTermTerminalButton *> *)terminalButtons NS_AVAILABLE_MAC(11) {
    NSMutableArray<iTermTerminalButton *> *updated = [NSMutableArray array];
    if (_hoverBlockFoldButton) {
        [updated addObject:_hoverBlockFoldButton];
    }
    if (_hoverBlockCopyButton) {
        [updated addObject:_hoverBlockCopyButton];
    }

    {
        id<VT100ScreenMarkReading> mark = [_delegate textViewSelectedCommandMark];
        DLog(@"mark=%@", mark);
        if (!mark.lineStyle && mark.command.length > 0 && [iTermAdvancedSettingsModel showButtonsForSelectedCommand]) {
            const NSRange intersectionRange = NSIntersectionRange(self.findOnPageHelper.absLineRange,
                                                                  [self visibleAbsoluteRangeIncludingOffscreenCommandLineIfVisible:NO]);
            if (intersectionRange.length > 0) {
                [updated addObjectsFromArray:[self commandButtonsForMark:mark
                                                                    line:intersectionRange.location - _dataSource.totalScrollbackOverflow + 1
                                                             shouldFloat:YES
                                                                offByOne:NO]];
            } else {
                DLog(@"No intersection between find on page helper's lineRange %@ and the visible absolute range %@",
                     NSStringFromRange(self.findOnPageHelper.absLineRange),
                     NSStringFromRange([self visibleAbsoluteRangeIncludingOffscreenCommandLineIfVisible:NO]));
            }
        }
    }

    NSArray<iTermTerminalButtonPlace *> *places = [self.dataSource buttonsInRange:self.rangeOfVisibleLines];
    __weak __typeof(self) weakSelf = self;
    [places enumerateObjectsUsingBlock:^(iTermTerminalButtonPlace * _Nonnull place, NSUInteger idx, BOOL * _Nonnull stop) {
        NSInteger i = [_buttons indexOfObjectPassingTest:^BOOL(iTermTerminalButton * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return (obj.id == place.id);
        }];
        if (i == NSNotFound || !VT100GridAbsCoordEquals([self absCoordForButton:_buttons[i]], place.coord)) {
            if (place.mark.copyBlockID) {
                iTermTerminalButton *button = [[[iTermTerminalCopyButton alloc] initWithID:place.id
                                                                                   blockID:place.mark.copyBlockID
                                                                                      mark:place.mark
                                                                                      absY:nil
                                                                                   tooltip:@"Copy Block to clipboard"] autorelease];
                NSString *blockID = [[place.mark.copyBlockID copy] autorelease];

                button.action = ^(NSPoint locationInWindow) {
                    [weakSelf copyBlock:blockID
                                absLine:-1
                       screenCoordinate:[weakSelf.window convertPointToScreen:locationInWindow]];
                };
                [updated addObject:button];
            } else if (place.mark.channelUID) {
                iTermTerminalButton *button = [[[iTermTerminalRevealChannelButton alloc] initWithPlace:place] autorelease];
                NSString *uid = [[place.mark.channelUID copy] autorelease];
                button.action = ^(NSPoint locationInWindow) {
                    [weakSelf revealChannelWithUID:uid];
                };
                [updated addObject:button];
            }
        } else {
            [updated addObject:_buttons[i]];
        }
    }];

    const int height = [self.dataSource height];
    const int firstLine = self.rangeOfVisibleLines.location;
    for (int i = firstLine; i < firstLine + height - 1; i++) {
        const int markLine = i + 1;
        id<VT100ScreenMarkReading> mark = [self.dataSource screenMarkOnLine:markLine];
        if (!mark.lineStyle) {
            continue;
        }
        if (!mark.command.length) {
            continue;
        }
        [updated addObjectsFromArray:[self commandButtonsForMark:mark line:markLine shouldFloat:NO offByOne:YES]];
    }

    [_buttons autorelease];
    _buttons = [updated retain];
    return _buttons;
}

- (void)revealChannelWithUID:(NSString *)uid {
    [self.delegate textViewRevealChannelWithUID:uid];
}

- (NSArray<iTermTerminalButton *> *)commandButtonsForMark:(id<VT100ScreenMarkReading>)mark
                                                     line:(int)markLine
                                              shouldFloat:(BOOL)shouldFloat
                                                 offByOne:(BOOL)offByOne NS_AVAILABLE_MAC(11)
{
    const int width = [self.dataSource width];
    const long long offset = self.dataSource.totalScrollbackOverflow;
    __weak __typeof(self) weakSelf = self;
    NSMutableArray<iTermTerminalButton *> *updated = [NSMutableArray array];
    __block int x = width - 2;

    // Helper block to add a button, reusing cached instance if available.
    void (^addButtonForClass)(Class, void(^)(NSPoint, id)) = ^(Class buttonClass, void(^actionBlock)(NSPoint, id)){
        iTermTerminalMarkButton *existing = [self cachedTerminalButtonForMark:mark ofClass:buttonClass];
        if (existing) {
            existing.shouldFloat = shouldFloat;
            [updated addObject:existing];
        } else {
            iTermTerminalMarkButton *button = [[buttonClass alloc] initWithMark:mark dx:(x - width)];
            button.shouldFloat = shouldFloat;
            __weak __typeof(mark) weakMark = mark;
            button.action = ^(NSPoint locationInWindow) {
                actionBlock(locationInWindow, weakMark);
            };
            [updated addObject:button];
        }
        x -= 3;
    };

    // Settings button.
    addButtonForClass([iTermTerminalSettingsButton class], ^(NSPoint locationInWindow, id weakMark) {
        [weakSelf popCommandSettingsButtonAt:locationInWindow for:weakMark];
    });

    // Copy command button.
    addButtonForClass([iTermTerminalCopyCommandButton class], ^(NSPoint locationInWindow, id weakMark) {
        [weakSelf popCommandCopyMenuAt:locationInWindow for:weakMark];
    });

    // Bookmark button.
    addButtonForClass([iTermTerminalBookmarkButton class], ^(NSPoint locationInWindow, id weakMark) {
        NSString *command = [weakMark command];
        if (command.length) {
            [weakSelf toggleBookmarkForMark:weakMark];
        }
    });

    // Share button.
    addButtonForClass([iTermTerminalShareButton class], ^(NSPoint locationInWindow, id weakMark) {
        [weakSelf popShareMenuAt:locationInWindow
                         absLine:(markLine + offset)
                         forMark:weakMark];
    });

    // Command info button.
    const long long absLine = markLine + offset;
    addButtonForClass([iTermCommandInfoButton class], ^(NSPoint locationInWindow, id weakMark) {
        if (weakMark) {
            [weakSelf presentCommandInfoForMark:weakMark
                             absoluteLineNumber:absLine
                                           date:[weakMark startDate]
                                          point:locationInWindow
                       fromOffscreenCommandLine:NO];
        }
    });

    // Fold / Unfold button.
    id<iTermFoldMarkReading> fold = [[self.dataSource foldMarksInRange:VT100GridRangeMake(markLine - (offByOne ? 0 : 1), 1)] firstObject];
    if (fold) {
        addButtonForClass([iTermTerminalUnfoldButton class], ^(NSPoint locationInWindow, id weakMark) {
            if (weakMark) {
                [weakSelf unfoldMark:fold];
            }
        });
    } else {
        addButtonForClass([iTermTerminalFoldButton class], ^(NSPoint locationInWindow, id weakMark) {
            if (weakMark) {
                [weakSelf foldCommandMark:weakMark];
            }
        });
    }

    return updated;
}

- (void)popCommandSettingsButtonAt:(NSPoint)locationInWindow for:(id<VT100ScreenMarkReading>)mark {
    iTermSimpleContextMenu *menu = [[[iTermSimpleContextMenu alloc] init] autorelease];
    __weak __typeof(self) weakSelf = self;
    [menu addItemWithTitle:@"Disable Command Selection" action:^{
        [iTermPreferences setBool:NO forKey:kPreferenceKeyClickToSelectCommand];
        [weakSelf.delegate textViewReloadSelectedCommand];
    }];
    [menu addItemWithTitle:@"Help" action:^{
        if (!weakSelf) {
            return;
        }
        NSString *filePath = [[NSBundle bundleForClass:[weakSelf class]] pathForResource:@"CommandSelectionHelp" ofType:@"md"];
        NSError *error = nil;
        NSString *content = [NSString stringWithContentsOfFile:filePath
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
        if (content) {
            [weakSelf it_showWarningWithMarkdown:content];
        }
    }];

    [menu showInView:self forEvent:NSApp.currentEvent];
}

- (void)popCommandCopyMenuAt:(NSPoint)locationInWindow for:(id<VT100ScreenMarkReading>)mark {
    if (![[mark retain] autorelease]) {
        return;
    }
    NSString *command = mark.command;

    iTermSimpleContextMenu *menu = [[[iTermSimpleContextMenu alloc] init] autorelease];
    if (command.length) {
        __weak __typeof(self) weakSelf = self;
        [menu addItemWithTitle:@"Copy Command" action:^{
            [weakSelf copyString:command];
            [ToastWindowController showToastWithMessage:@"Command Copied"
                                               duration:1.5
                                topLeftScreenCoordinate:[weakSelf.window convertPointToScreen:locationInWindow]
                                              pointSize:12];
        }];
        [menu addItemWithTitle:@"Copy Output" action:^{
            iTermRenegablePromise<NSString *> *promise = [self promisedOutputForMark:mark progress:nil];
            [[promise wait] whenFirst:^(NSString * _Nonnull string) {
                [weakSelf copyString:string];
                [ToastWindowController showToastWithMessage:@"Output Copied"
                                                   duration:1.5
                                    topLeftScreenCoordinate:[weakSelf.window convertPointToScreen:locationInWindow]
                                                  pointSize:12];
            } second:^(NSError * _Nonnull object) {
                DLog(@"%@", object);
            }];
        }];
    }

    [menu showInView:self forEvent:NSApp.currentEvent];
}

- (iTermSelection *)selectionForCommandAndOutputOfMark:(id<VT100ScreenMarkReading>)mark {
    const VT100GridAbsCoordRange absRange = [self.delegate textViewCoordRangeForCommandAndOutputAtMark:mark];
    iTermSelection *selection = [[[iTermSelection alloc] init] autorelease];
    selection.delegate = self;
    [selection beginSelectionAtAbsCoord:absRange.start
                                   mode:kiTermSelectionModeLine
                                 resume:NO
                                 append:NO];
    [selection moveSelectionEndpointTo:absRange.end];
    [selection endLiveSelection];
    return selection;
}

- (iTermRenegablePromise<NSAttributedString *> *)promisedAttributedStringForCommandAndOutputOfMark:(id<VT100ScreenMarkReading>)mark {
    iTermRenegablePromise<NSAttributedString *> *promise =
        [self promisedAttributedStringForSelectedTextCappedAtSize:INT_MAX
                                                minimumLineNumber:0
                                                       timestamps:NO
                                                        selection:[self selectionForCommandAndOutputOfMark:mark]];
    return promise;
}

- (NSURL *)commandURLForMark:(id<VT100ScreenMarkReading>)mark 
                     absLine:(long long)absLine {
    return [iTermCommandURLBuilder urlWithMark:mark absLine:absLine dataSource:self.dataSource];
}

- (void)popShareMenuAt:(NSPoint)locationInWindow 
               absLine:(long long)absLine
               forMark:(id<VT100ScreenMarkReading>)mark {
    if (![[mark retain] autorelease]) {
        return;
    }

    iTermCommandShareMenuProvider *provider =
    [[[iTermCommandShareMenuProvider alloc] initWithMark:mark
                                         promisedContent:[self promisedAttributedStringForCommandAndOutputOfMark:mark]
                                  defaultBackgroundColor:[self defaultBackgroundColor]
                                              commandURL:[self commandURLForMark:mark
                                                                         absLine:absLine]] autorelease];
    [provider popWithLocationInWindow:locationInWindow view:self];
}

- (void)toggleBookmarkForMark:(id<VT100ScreenMarkReading>)mark {
    if (!mark) {
        return;
    }
    if (mark.name) {
        [self.delegate textViewRemoveBookmarkForMark:mark];
    } else {
        [iTermBookmarkDialogViewController showInWindow:self.window
                                         withCompletion:^(NSString * _Nonnull name) {
            [self.delegate textViewSaveScrollPositionForMark:mark withName:name];
        }];
    }
}

- (iTermTerminalMarkButton *)cachedTerminalButtonForMark:(id<VT100ScreenMarkReading>)mark
                                                 ofClass:(Class)desiredClass NS_AVAILABLE_MAC(11) {
    return [iTermTerminalMarkButton castFrom:[_buttons objectPassingTest:^BOOL(iTermTerminalButton *genericButton, NSUInteger index, BOOL *stop) {
        iTermTerminalMarkButton *button = [iTermTerminalMarkButton castFrom:genericButton];
        if (!button) {
            return NO;
        }
        if (![button isKindOfClass:desiredClass]) {
            return NO;
        }
        return button.screenMark == mark || [button.screenMark.guid isEqualToString:mark.guid];
    }]];
}

- (void)copyBlock:(NSString *)block absLine:(long long)absLine screenCoordinate:(NSPoint)screenCoordinate {
    if ([self copyBlock:block includingAbsLine:absLine]) {
        [ToastWindowController showToastWithMessage:@"Copied"
                                           duration:1
                            topLeftScreenCoordinate:screenCoordinate
                                          pointSize:12];
    }
}

- (void)unfoldBlock:(NSString *)blockID {
    const VT100GridCoordRange range = [self.dataSource rangeOfBlockWithID:blockID];
    if (range.start.x < 0){
        DLog(@"Failed to find block %@", blockID);
        return;
    }
    const long long offset = [self.dataSource totalScrollbackOverflow];
    [self unfoldAbsoluteLineRange:NSMakeRange(range.start.y + offset,
                                              range.end.y - range.start.y + 1)];
    [self didFoldOrUnfold];
}

- (void)foldBlock:(NSString *)blockID {
    const VT100GridCoordRange range = [self.dataSource rangeOfBlockWithID:blockID];
    if (range.start.x < 0 || range.start.y == range.end.y) {
        DLog(@"Failed to fold block %@. range=%@", blockID, VT100GridCoordRangeDescription(range));
        return;
    }
    const long long offset = [self.dataSource totalScrollbackOverflow];
    [self foldRange:NSMakeRange(range.start.y + offset,
                                range.end.y - range.start.y + 1)];
    [self didFoldOrUnfold];
}

- (void)didFoldOrUnfold {
    [self.delegate textViewReloadSelectedCommand];
    [self.selection clearSelection];
}

- (void)updateButtonHover:(NSPoint)locationInWindow pressed:(BOOL)pressed {
    NSPoint point = [self convertPoint:locationInWindow fromView:nil];
    DLog(@"updateHover location=%@ pressed=%@", NSStringFromPoint(locationInWindow), @(pressed));
    if (@available(macOS 11, *)) {
        BOOL changed = NO;
        for (iTermTerminalButton *button in self.terminalButtons) {
            if (NSPointInRect(point, button.desiredFrame)) {
                DLog(@"mouse is over %@", button);
                // Mouse over button
                if (pressed) {
                    changed = [button mouseDownInside] || changed;
                } else if (button.pressed) {
                    DLog(@"button was pressed");
                    [button mouseUpWithLocationInWindow:locationInWindow];
                    changed = YES;
                }
            } else {
                // Mouse not over button
                if (pressed) {
                    changed = [button mouseDownOutside] || changed;
                } else if (button.pressed) {
                    DLog(@"button was pressed");
                    [button mouseUpWithLocationInWindow:locationInWindow];
                    changed = YES;
                }
            }
        }
        if (changed) {
            [self requestDelegateRedraw];
        }
    }
}

#pragma mark - Accessibility

// See WebCore's FrameSelectionMac.mm for the inspiration.
- (CGRect)accessibilityConvertScreenRect:(CGRect)bounds {
    NSArray *screens = [NSScreen screens];
    if ([screens count]) {
        CGFloat screenHeight = NSHeight([(NSScreen *)[screens objectAtIndex:0] frame]);
        NSRect rect = bounds;
        rect.origin.y = (screenHeight - (bounds.origin.y + bounds.size.height));
        AccLog(@"accessibilityConvertScreenRect:%@ -> %@", NSStringFromRect(bounds), NSStringFromRect(rect));
        return rect;
    }
    AccLog(@"accessibilityConvertScreenRect:%@ -> %@ [fail]", NSStringFromRect(bounds), NSStringFromRect(CGRectZero));
    return CGRectZero;
}

// These two are needed to make "Enable Full Keyboard Access" able to send spaces. Issue 10023.
- (void)setAccessibilityContents:(NSArray *)accessibilityContents {
    AccLog(@"setAccessibilityContents::%@", accessibilityContents);
}

- (void)setAccessibilityValue:(id)accessibilityValue {
    AccLog(@"setAccessibilityValue:%@", accessibilityValue);
}

- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSInteger)accessibilityLineForIndex:(NSInteger)index {
    const NSInteger line = [_accessibilityHelper lineForIndex:index];
    AccLog(@"accessibilityLineForIndex:%@ -> %@", @(index), @(line));
    return line;
}

static NSString *iTermStringFromRange(NSRange range) {
    if (range.location == NSNotFound) {
        return [NSString stringWithFormat:@"[NSNotFound, length %@]", @(range.length)];
    }
    if (range.length == 0) {
        return [NSString stringWithFormat:@"[Empty range at %@]", @(range.location)];
    }
    return [NSString stringWithFormat:@"[%@…%@]", @(range.location), @(NSMaxRange(range) - 1)];
}

- (NSRange)accessibilityRangeForLine:(NSInteger)line {
    const NSRange range = [_accessibilityHelper rangeForLine:line];
    AccLog(@"accessibilityRangeForLine:%@ -> %@", @(line), iTermStringFromRange(range));
    return range;
}

- (NSString *)accessibilityStringForRange:(NSRange)range {
    NSString *const string = [_accessibilityHelper stringForRange:range];
    AccLog(@"accessibilityStringForRange:%@ -> “%@”", iTermStringFromRange(range), [string it_sanitized]);
    return string;
}

- (NSRange)accessibilityRangeForPosition:(NSPoint)point {
    const NSRange range = [_accessibilityHelper rangeForPosition:point];
    AccLog(@"accessibilityRangeForPosition:%@ -> %@", NSStringFromPoint(point), iTermStringFromRange(range));
    return range;
}

- (NSRange)accessibilityRangeForIndex:(NSInteger)index {
    const NSRange range = [_accessibilityHelper rangeOfIndex:index];
    AccLog(@"accessibilityRangeForIndex:%@ -> %@", @(index), iTermStringFromRange(range));
    return range;
}

- (NSRect)accessibilityFrameForRange:(NSRange)range {
    const NSRect frame = [_accessibilityHelper boundsForRange:range];
    AccLog(@"accessibilityFrameForRange:%@ -> %@", iTermStringFromRange(range), NSStringFromRect(frame));
    return frame;
}

- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range {
    NSAttributedString *string = [_accessibilityHelper attributedStringForRange:range];
    AccLog(@"accessibilityAttributedStringForRange:%@ -> “%@”", iTermStringFromRange(range), string.string.it_sanitized);
    return string;
}

- (NSAccessibilityRole)accessibilityRole {
    const NSAccessibilityRole role = [_accessibilityHelper role];
    AccLog(@"accessibilityRole -> %@", role);
    return role;
}

- (NSString *)accessibilityRoleDescription {
    NSString *const description = [_accessibilityHelper roleDescription];
    AccLog(@"accessibilityRoleDescription -> %@", description);
    return description;
}

- (NSString *)accessibilityHelp {
    NSString *help = [_accessibilityHelper help];
    AccLog(@"accessibilityHelp -> %@", help);
    return help;
}

- (BOOL)isAccessibilityFocused {
    const BOOL focused = [_accessibilityHelper focused];
    AccLog(@"isAccessibilityFocused -> %@", @(focused));
    return focused;
}

- (NSString *)accessibilityLabel {
    NSString *const label = [_accessibilityHelper label];
    AccLog(@"accessibilityLabel -> %@", label);
    return label;
}

- (id)accessibilityValue {
    NSString *value = [_accessibilityHelper allText];
    AccLog(@"accessibilityValue -> %@", value.it_sanitized);
    return value;
}

- (NSInteger)accessibilityNumberOfCharacters {
    const NSInteger number = [_accessibilityHelper numberOfCharacters];
    AccLog(@"accessibilityNumberOfCharacters -> %@", @(number));
    return number;
}

- (NSString *)accessibilitySelectedText {
    NSString *selected = [_accessibilityHelper selectedText];
    AccLog(@"accessibilitySelectedText -> %@", selected.it_sanitized);
    return selected;
}

- (NSRange)accessibilitySelectedTextRange {
    const NSRange range = [_accessibilityHelper selectedTextRange];
    AccLog(@"accessibilitySelectedTextRange -> %@", iTermStringFromRange(range));
    return range;
}

- (NSArray<NSValue *> *)accessibilitySelectedTextRanges {
    NSArray<NSValue *> *ranges = [_accessibilityHelper selectedTextRanges];
    AccLog(@"accessibilitySelectedTextRanges -> %@", [[ranges mapWithBlock:^id(NSValue *anObject) {
        return iTermStringFromRange([anObject rangeValue]);
    }] componentsJoinedByString:@", "]);
    return ranges;
}

- (NSInteger)accessibilityInsertionPointLineNumber {
    const NSInteger line = [_accessibilityHelper insertionPointLineNumber];
    AccLog(@"accessibilityInsertionPointLineNumber -> %@", @(line));
    return line;
}

- (NSRange)accessibilityVisibleCharacterRange {
    const NSRange range = [_accessibilityHelper visibleCharacterRange];
    AccLog(@"accessibilityVisibleCharacterRange -> %@", iTermStringFromRange(range));
    return range;
}

- (NSString *)accessibilityDocument {
    NSString *const doc = [[_accessibilityHelper currentDocumentURL] absoluteString];
    AccLog(@"accessibilityDocument -> %@", doc);
    return doc;
}

- (void)setAccessibilitySelectedTextRange:(NSRange)accessibilitySelectedTextRange {
    AccLog(@"setAccessibilitySelectedTextRange:%@", iTermStringFromRange(accessibilitySelectedTextRange));
    [_accessibilityHelper setSelectedTextRange:accessibilitySelectedTextRange];
}

#pragma mark - Accessibility Helper Delegate

- (int)accessibilityHelperAccessibilityLineNumberForLineNumber:(int)actualLineNumber {
    int numberOfLines = [_dataSource numberOfLines];
    int offset = MAX(0, numberOfLines - [iTermAdvancedSettingsModel numberOfLinesForAccessibility]);
    return actualLineNumber - offset;
}

- (int)accessibilityHelperLineNumberForAccessibilityLineNumber:(int)accessibilityLineNumber {
    int numberOfLines = [_dataSource numberOfLines];
    int offset = MAX(0, numberOfLines - [iTermAdvancedSettingsModel numberOfLinesForAccessibility]);
    return accessibilityLineNumber + offset;
}

// WARNING! accessibilityScreenPosition is idiotic: y=0 is the top of the main screen and it increases going down.
- (VT100GridCoord)accessibilityHelperCoordForPoint:(NSPoint)accessibilityScreenPosition {
    const NSPoint locationInTextView = [self viewPointFromAccessibilityScreenPoint:accessibilityScreenPosition];
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    int x = (locationInTextView.x - [iTermPreferences intForKey:kPreferenceKeySideMargins] - visibleRect.origin.x) / _charWidth;
    int y = locationInTextView.y / _lineHeight;
    return VT100GridCoordMake(x, [self accessibilityHelperAccessibilityLineNumberForLineNumber:y]);
}

- (NSRect)accessibilityHelperFrameForCoordRange:(VT100GridCoordRange)coordRange {
    coordRange.start.y = [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.start.y];
    coordRange.end.y = [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.end.y];
    NSRect result = NSMakeRect(MAX(0, floor(coordRange.start.x * _charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins])),
                               MAX(0, coordRange.start.y * _lineHeight),
                               MAX(0, (coordRange.end.x - coordRange.start.x) * _charWidth),
                               MAX(0, (coordRange.end.y - coordRange.start.y + 1) * _lineHeight));
    result = [self convertRect:result toView:nil];
    result = [self.window convertRectToScreen:result];
    return result;
}

- (VT100GridCoord)accessibilityHelperCursorCoord {
    int y = [_dataSource numberOfLines] - [_dataSource height] + [_dataSource cursorY] - 1;
    return VT100GridCoordMake([_dataSource cursorX] - 1,
                              [self accessibilityHelperAccessibilityLineNumberForLineNumber:y]);
}

- (void)accessibilityHelperSetSelectedRange:(VT100GridCoordRange)coordRange {
    AccLog(@"accessibilityHelperSetSelectedRange:%@", VT100GridCoordRangeDescription(coordRange));
    coordRange.start.y =
        [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.start.y];
    coordRange.end.y =
        [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.end.y];
    [_selection clearSelection];
    const long long overflow = _dataSource.totalScrollbackOverflow;
    [_selection beginSelectionAtAbsCoord:VT100GridAbsCoordFromCoord(coordRange.start, overflow)
                            mode:kiTermSelectionModeCharacter
                          resume:NO
                          append:NO];
    [_selection moveSelectionEndpointTo:VT100GridAbsCoordFromCoord(coordRange.end, overflow)];
    [_selection endLiveSelection];
}

- (VT100GridCoordRange)accessibilityRangeOfCursor {
    VT100GridCoord coord = [self accessibilityHelperCursorCoord];
    return VT100GridCoordRangeMake(coord.x, coord.y, coord.x, coord.y);
}

- (VT100GridCoordRange)accessibilityHelperSelectedRange {
    iTermSubSelection *sub = _selection.allSubSelections.lastObject;

    if (!sub) {
        return [self accessibilityRangeOfCursor];
    }
    __block VT100GridCoordRange coordRange = [self accessibilityRangeOfCursor];
    [self withRelativeCoordRange:sub.absRange.coordRange block:^(VT100GridCoordRange initialCoordRange) {
        coordRange = initialCoordRange;
        coordRange.start.y = MAX(0, [self accessibilityHelperAccessibilityLineNumberForLineNumber:coordRange.start.y]);
        coordRange.end.y = MAX(0, [self accessibilityHelperAccessibilityLineNumberForLineNumber:coordRange.end.y]);
    }];
    return coordRange;
}

- (NSString *)accessibilityHelperSelectedText {
    return [self selectedTextWithStyle:iTermCopyTextStylePlainText
                          cappedAtSize:0
                     minimumLineNumber:[self accessibilityHelperLineNumberForAccessibilityLineNumber:0]
                            timestamps:NO
                             selection:self.selection];
}

- (NSURL *)accessibilityHelperCurrentDocumentURL {
    return [_delegate textViewCurrentLocation];
}

- (const screen_char_t *)accessibilityHelperLineAtIndex:(int)accessibilityIndex continuation:(screen_char_t *)continuation {
    ScreenCharArray *sca = [_dataSource screenCharArrayForLine:[self accessibilityHelperLineNumberForAccessibilityLineNumber:accessibilityIndex]];
    if (continuation) {
        *continuation = sca.continuation;
    }
    return sca.line;
}

- (int)accessibilityHelperWidth {
    return [_dataSource width];
}

- (int)accessibilityHelperNumberOfLines {
    return MIN([iTermAdvancedSettingsModel numberOfLinesForAccessibility],
               [_dataSource numberOfLines]);
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
    NSPopover *popover = notification.object;
    iTermWebViewWrapperViewController *viewController = (iTermWebViewWrapperViewController *)popover.contentViewController;
    [viewController terminateWebView];

}

#pragma mark - iTermKeyboardHandlerDelegate

- (BOOL)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
    shouldHandleKeyDown:(NSEvent *)event {
    if (![_delegate textViewShouldAcceptKeyDownEvent:event]) {
        return NO;
    }
    if (!_selection.live && [iTermAdvancedSettingsModel typingClearsSelection]) {
        // Remove selection when you type, unless the selection is live because it's handy to be
        // able to scroll up, click, hit a key, and then drag to select to (near) the end. See
        // issue 3340.
        [self deselect];
    }
    // Generally, find-on-page continues from the last result. If you press a
    // key then it starts searching from the bottom again.
    [_findOnPageHelper resetFindCursor];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iTermApplicationDelegate *appDelegate = [iTermApplication.sharedApplication delegate];
        [appDelegate userDidInteractWithASession];
    });
    if ([_delegate isPasting]) {
        [_delegate queueKeyDown:event];
        return NO;
    }
    if ([_delegate textViewDelegateHandlesAllKeystrokes]) {
        DLog(@"PTYTextView keyDown: in instant replay, send to delegate");
        // Delegate has special handling for this case.
        [_delegate keyDown:event];
        return NO;
    }

    return YES;
}

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
            loadContext:(iTermKeyboardHandlerContext *)context
               forEvent:(NSEvent *)event {
    context->hasActionableKeyMapping = [_delegate hasActionableKeyMappingForEvent:event];
    context->leftOptionKey = [_delegate optionKey];
    context->rightOptionKey = [_delegate rightOptionKey];
    context->autorepeatMode = [_dataSource terminalAutorepeatMode];
}

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
     interpretKeyEvents:(NSArray<NSEvent *> *)events {
    [self interpretKeyEvents:events];
}

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
  sendEventToController:(NSEvent *)event {
    [self.delegate keyDown:event];
}

- (NSRange)keyboardHandlerMarkedTextRange:(iTermKeyboardHandler *)keyboardhandler {
    return _drawingHelper.inputMethodMarkedRange;
}

- (void)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler
             insertText:(NSString *)aString {
    if ([self hasMarkedText]) {
        DLog(@"insertText: clear marked text");
        [self invalidateInputMethodEditorRect];
        _drawingHelper.inputMethodMarkedRange = NSMakeRange(0, 0);
        _drawingHelper.markedText = nil;
        _drawingHelper.numberOfIMELines = 0;
    }

    if (![_selection hasSelection]) {
        [self resetFindCursor];
    }

    if ([aString length] > 0) {
        if ([_delegate respondsToSelector:@selector(insertText:)]) {
            [_delegate insertText:aString];
        } else {
            [super insertText:aString];
        }
    }
    if ([self hasMarkedText]) {
        // In case imeOffset changed, the frame height must adjust.
        [_delegate refresh];
    }
}

- (NSInteger)keyboardHandlerWindowNumber:(iTermKeyboardHandler *)keyboardhandler {
    return self.window.windowNumber;
}

- (BOOL)keyboardHandler:(iTermKeyboardHandler *)keyboardhandler shouldBackspaceAt:(NSUInteger)location {
    const NSRange cursorRange = [self nsrangeOfCursor];
    DLog(@"cursor range=%@ location=%@", @(NSMaxRange(cursorRange)), @(location));
    return NSMaxRange(cursorRange) == location;
}

#pragma mark - iTermBadgeLabelDelegate

- (NSSize)badgeLabelSizeFraction {
    return [self.delegate badgeLabelSizeFraction];
}

- (NSFont *)badgeLabelFontOfSize:(CGFloat)pointSize {
    return [self.delegate badgeLabelFontOfSize:pointSize];
}

#pragma mark - iTermSpecialHandlerForAPIKeyDownNotifications

- (void)handleSpecialKeyDown:(NSEvent *)event {
    [self.delegate textViewhandleSpecialKeyDown:event];
}

- (void)setBlinkingCursor:(BOOL)blinkingCursor {
    _blinkingCursor = blinkingCursor;
    DLog(@"%@", [NSThread callStackSymbols]);
}

- (void)setCursorShadow:(BOOL)cursorShadow {
    _drawingHelper.cursorShadow = cursorShadow;
}

- (void)setHideCursorWhenUnfocused:(BOOL)hideCursorWhenUnfocused {
    _drawingHelper.hideCursorWhenUnfocused = hideCursorWhenUnfocused;
}

- (BOOL)hideCursorWhenUnfocused {
    return _drawingHelper.hideCursorWhenUnfocused;
}

- (BOOL)cursorShadow {
    return _drawingHelper.cursorShadow;
}

#pragma mark - PTYNoteViewControllerDelegate

- (void)noteDidRequestRemoval:(PTYNoteViewController *)note {
    const iTermWarningSelection selection = [iTermWarning showWarningWithTitle:@"Really remove annotation?"
                                                                       actions:@[ @"OK", @"Cancel" ]
                                                                     accessory:nil
                                                                    identifier:@"NoSyncConfirmRemoveAnnotation"
                                                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                                                       heading:@"Confirm"
                                                                        window:self.window];
    if (selection == kiTermWarningSelection1) {
        return;
    }
    [self.dataSource removeAnnotation:note.annotation];
    [self removeNote:note];
    [self.window makeFirstResponder:self];
}

// This removes the view controller and view. It assumes the PTYAnnotation was already removed from the datasource.
- (void)removeNote:(PTYNoteViewController *)note {
    [note.view removeFromSuperview];
    [_notes removeObject:note];
    [self updateAlphaValue];
}

- (void)noteDidEndEditing:(PTYNoteViewController *)note {
    [self.window makeFirstResponder:self];
}

- (void)noteVisibilityDidChange:(PTYNoteViewController *)note {
    if (!note.isNoteHidden) {
        [self setAlphaValue:1];
        return;
    }
    [self updateAlphaValue];
}

- (void)noteWillBeRemoved:(PTYNoteViewController *)note {
    [self removeNote:note];
}

- (void)note:(PTYNoteViewController *)note setAnnotation:(id<PTYAnnotationReading>)annotation stringValue:(NSString *)stringValue {
    [_dataSource setStringValueOfAnnotation:annotation to:stringValue];
}

- (BOOL)shouldBeAlphaedOut {
    return ([self allAnnotationsAreHidden] &&
            !self.hasPortholes &&
            self.contentNavigationShortcuts.count == 0);
}
- (void)updateAlphaValue {
    if ([self shouldBeAlphaedOut]) {
        [self setAlphaValue:0.0];
    } else {
        [self setAlphaValue:1.0];
    }
}

- (BOOL)allAnnotationsAreHidden {
    return [_notes allWithBlock:^BOOL(PTYNoteViewController *note) {
        return note.isNoteHidden;
    }];
}

- (VT100GridCoordRange)rangeOfBlockIncludingLine:(long long)absLine
                          blockID:(NSString *)block {
    int start;
    const long long offset = self.dataSource.totalScrollbackOverflow;
    if (absLine < offset) {
        start = 0;
        if (![[self blockIDsOnLine:start] containsObject:block]) {
            DLog(@"Start line is not the same block");
            return VT100GridCoordRangeMake(-1, -1, -1, -1);
        }
    } else {
        start = absLine - offset;
    }
    
    while (start - 1 >= 0 && [[self blockIDsOnLine:start - 1] containsObject:block]) {
        start -= 1;
    }
    int end = start;
    const int count = [self.dataSource numberOfLines];
    while (end + 1 < count && [[self blockIDsOnLine:end + 1] containsObject:block]) {
        end += 1;
    }
    
    return VT100GridCoordRangeMake(0,
                                     start,
                                     self.dataSource.width,
                                     end);
}

- (BOOL)copyBlock:(NSString *)block includingAbsLine:(long long)absLine {
    if (absLine < 0) {
        const VT100GridCoordRange range = [self.dataSource rangeOfBlockWithID:block];
        if (range.start.x < 0) {
            return NO;
        }
        return [self copyTextInRange:range];
    }
    const VT100GridCoordRange range = [self rangeOfBlockIncludingLine:absLine blockID:block];
    if (range.start.x < 0) {
        return NO;
    }
    return [self copyTextInRange:range];
}

- (BOOL)copyTextInRange:(VT100GridCoordRange)range {
    NSString *string = [self stringForPortholeInRange:range];
    if (!string) {
        iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
        const VT100GridWindowedRange windowedRange = VT100GridWindowedRangeMake(range, 0, 0);
        string = [extractor contentInRange:windowedRange
                         attributeProvider:nil
                                nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                       pad:NO
                        includeLastNewline:YES
                    trimTrailingWhitespace:YES
                              cappedAtSize:-1
                              truncateTail:YES
                         continuationChars:nil
                                    coords:nil];
    }
    if (string.length > 0) {
        [self copyString:string];
        return YES;
    }
    return NO;
}

- (NSArray<NSString *> *)blockIDsOnLine:(int)line {
    return [[self blockIDListForLine:line] componentsSeparatedByString:iTermExternalAttributeBlockIDDelimiter];
}

- (NSString *)blockIDListForLine:(int)line {
    id<iTermExternalAttributeIndexReading> eaIndex = [_dataSource externalAttributeIndexForLine:line];
    if (!eaIndex) {
        return nil;
    }
    NSString *blockIDList = eaIndex.attributes[@0].blockIDList;
    return blockIDList;
}

@end

@implementation PTYTextView(MouseHandler)

- (void)refuseFirstResponderAtCurrentMouseLocation {
    [_focusFollowsMouse refuseFirstResponderAtCurrentMouseLocation];
}

- (BOOL)mouseHandlerViewHasFocus:(PTYMouseHandler *)handler {
    return [[iTermController sharedInstance] frontTextView] == self;
}

- (void)mouseHandlerMakeKeyAndOrderFrontAndMakeFirstResponderAndActivateApp:(PTYMouseHandler *)sender {
    [[self window] makeKeyAndOrderFront:nil];
    [[self window] makeFirstResponder:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)mouseHandlerMakeFirstResponder:(PTYMouseHandler *)handler {
    [_delegate textViewDidReceiveSingleClick];
    [[self window] makeFirstResponder:self];
}

- (void)mouseHandlerWillBeginDragPane:(PTYMouseHandler *)handler {
    [_delegate textViewBeginDrag];
}

- (BOOL)mouseHandlerIsInKeyWindow:(PTYMouseHandler *)handler {
    return ([NSApp keyWindow] == [self window]);
}

- (VT100GridCoord)mouseHandler:(PTYMouseHandler *)handler
                    clickPoint:(NSEvent *)event
                 allowOverflow:(BOOL)allowRightMarginOverflow
                    firstMouse:(BOOL)firstMouse {
    if (event.type == NSEventTypeLeftMouseUp && event.clickCount == 1) {
        DLog(@"mouseUp: textview handling single click");
        const NSPoint windowPoint = [event locationInWindow];
        const NSPoint enclosingViewPoint = [self.enclosingScrollView convertPoint:windowPoint fromView:nil];
        const NSPoint pointInSelf = [self.enclosingScrollView convertPoint:enclosingViewPoint toView:self];
        NSString *message = [_indicatorsHelper helpTextForIndicatorAt:enclosingViewPoint
                                                            sessionID:[_delegate.textViewVariablesScope valueForVariableName:iTermVariableKeySessionID]];
        if (message) {
            DLog(@"mouseUp: show indicator message");
            [self showIndicatorMessage:message at:enclosingViewPoint];
            return VT100GridCoordMake(-1, -1);
        }
        if (_drawingHelper.offscreenCommandLine) {
            DLog(@"mouseUp: reveal command line");
            NSRect rect = [iTermTextDrawingHelper offscreenCommandLineFrameForVisibleRect:[self adjustedDocumentVisibleRect]
                                                                                 cellSize:NSMakeSize(_charWidth, _lineHeight)
                                                                                 gridSize:VT100GridSizeMake(_dataSource.width, _dataSource.height)];
            const NSPoint viewPoint = [self convertPoint:windowPoint fromView:nil];
            if (NSPointInRect(viewPoint, rect)) {
                DLog(@"Highlight %@", @(_drawingHelper.offscreenCommandLine.absoluteLineNumber));
                [self highlightMarkOnLine:_drawingHelper.offscreenCommandLine.absoluteLineNumber - _dataSource.totalScrollbackOverflow
                             hasErrorCode:NO];
                [self scrollToAbsoluteOffset:_drawingHelper.offscreenCommandLine.absoluteLineNumber height:1];
                return VT100GridCoordMake(-1, -1);
            }
        }
        id<iTermFoldMarkReading> foldMark = [self foldMarkAtWindowCoord:event.locationInWindow];
        id<VT100ScreenMarkReading> commandMark = [self commandMarkAtWindowCoord:event.locationInWindow];
        id<iTermPathMarkReading> pathMark = [self pathMarkAtWindowCoord:event.locationInWindow];
        const VT100GridCoord coord = [self coordForPoint:pointInSelf allowRightMarginOverflow:NO];
        NSString *blockID = [self foldableBlockIDOnLine:coord.y];
        if (foldMark) {
            DLog(@"mouseUp: fold mark");
            [self unfoldMark:foldMark];
            return VT100GridCoordMake(-1, -1);
        } else if (pointInSelf.x < [iTermPreferences intForKey:kPreferenceKeySideMargins] + PTYTextViewMarginClickGraceWidth &&
                   pointInSelf.x >= 0 &&
                   blockID != nil) {
            DLog(@"Clicked on unfolded block indicator");
            [self foldBlock:blockID];
        } else if (commandMark) {
            DLog(@"mouseUp: command mark");
            [self foldCommandMark:commandMark];
            return VT100GridCoordMake(-1, -1);
        } else if (pathMark) {
            __weak __typeof(self) weakSelf = self;
            [_selectCommandTimer release];
            _selectCommandTimer = nil;
            _selectCommandTimer = [[NSTimer scheduledTimerWithTimeInterval:[NSEvent doubleClickInterval]
                                                                   repeats:NO
                                                                     block:^(NSTimer * _Nonnull timer) {
                [weakSelf openPathMark:pathMark];
            }] retain];
        } else if (!firstMouse) {
            if ([self revealAnnotationsAt:[self coordForEvent:event] toggle:YES]) {
                DLog(@"mouseUp: reveal annotation");
                return VT100GridCoordMake(-1, -1);
            }
            const NSPoint temp =
            [self clickPoint:event allowRightMarginOverflow:allowRightMarginOverflow];
            const VT100GridCoord selectAtCoord = VT100GridCoordMake(temp.x, temp.y);

            [_selectCommandTimer invalidate];
            [_selectCommandTimer release];
            _selectCommandTimer = nil;

            if ([iTermAdvancedSettingsModel useDoubleClickDelayForCommandSelection] &&
                [_delegate textViewMarkForCommandAt:selectAtCoord] != [_delegate textViewSelectedCommandMark]) {
                DLog(@"mouseUp: start timer for command selection");
                __weak __typeof(self) weakSelf = self;
                _selectCommandTimer = [[NSTimer scheduledTimerWithTimeInterval:[NSEvent doubleClickInterval]
                                                                       repeats:NO
                                                                         block:^(NSTimer * _Nonnull timer) {
                    [weakSelf selectCommandAt:selectAtCoord];
                }] retain];
            } else if (!handler.lastMouseDownRemovedSelection) {
                DLog(@"mouseUp: select a command");
                [self selectCommandAt:selectAtCoord];
            }
        }
    }
    const NSPoint temp =
    [self clickPoint:event allowRightMarginOverflow:allowRightMarginOverflow];
    return VT100GridCoordMake(temp.x, temp.y);
}

- (void)openPathMark:(id<iTermPathMarkReading>)pathMark {
    [_selectCommandTimer release];
    _selectCommandTimer = nil;
    [self.delegate textViewUserDidClickPathMark:pathMark];
}

- (void)mouseHandlerCancelSingleClick:(PTYMouseHandler *)sender {
    [_selectCommandTimer release];
    _selectCommandTimer = nil;
    [self.delegate textViewCancelSingleClick];
}

- (void)selectCommandAt:(VT100GridCoord)coord {
    [_delegate textViewSelectCommandRegionAtCoord:coord];
    [_selectCommandTimer release];
    _selectCommandTimer = nil;
}

- (void)mouseHandler:(PTYMouseHandler *)sender handleCommandShiftClickAtCoord:(VT100GridCoord)coord {
    id<VT100ScreenMarkReading> mark = [_delegate textViewMarkForCommandAt:coord];
    if (!mark) {
        return;
    }
    const VT100GridCoordRange range = [self coordRangeForMark:mark];
    if (!VT100GridCoordRangeContainsCoord(range, coord)) {
        return;
    }

    const long long overflow = [_dataSource totalScrollbackOverflow];
    [_selection beginSelectionAtAbsCoord:VT100GridAbsCoordMake(0, range.start.y + overflow)
                                   mode:kiTermSelectionModeLine
                                 resume:NO
                                 append:NO];
    [_selection moveSelectionEndpointTo:VT100GridAbsCoordMake(self.dataSource.width, range.end.y + overflow - 1)];
    [_selection endLiveSelection];
}

- (BOOL)mouseHandlerInUnderlinedRangeForEvent:(NSEvent *)event {
    const VT100GridCoord coord = [self coordForEvent:event];
    DLog(@"coord=%@", VT100GridCoordDescription(coord));
    if (VT100GridCoordEquals(coord, VT100GridCoordInvalid)) {
        return NO;
    }
    const VT100GridAbsCoord absCoord = VT100GridAbsCoordFromCoord(coord, self.dataSource.totalScrollbackOverflow);
    const VT100GridAbsWindowedRange underlinedRange = _drawingHelper.underlinedRange;
    DLog(@"underlinedRange=%@", VT100GridAbsWindowedRangeDescription(underlinedRange));
    return VT100GridAbsWindowedRangeContainsAbsCoord(underlinedRange, absCoord);
}

- (BOOL)mouseHandler:(PTYMouseHandler *)handler
      coordIsMutable:(VT100GridCoord)coord {
    return [self coordinateIsInMutableArea:coord];
}

- (MouseMode)mouseHandlerMouseMode:(PTYMouseHandler *)handler {
    return _dataSource.terminalMouseMode;
}

- (void)mouseHandlerDidSingleClick:(PTYMouseHandler *)handler event:(NSEvent *)event {
    const VT100GridCoord coord = [self coordForEvent:event];
    const VT100GridCoordRange coordRange =
        VT100GridCoordRangeMake(coord.x,
                                coord.y,
                                coord.x + 1,
                                coord.y);
    if ([[self.dataSource annotationsInRange:coordRange] count]) {
        // If you clicked on an annotation we want to toggle it, not hide all of them.
        return;
    }

    [self hideAllAnnotations];
}

- (iTermSelection *)mouseHandlerCurrentSelection:(PTYMouseHandler *)handler {
    return _selection;
}

- (id<iTermImageInfoReading>)mouseHandler:(PTYMouseHandler *)handler imageAt:(VT100GridCoord)coord {
    return [self imageInfoAtCoord:coord];
}

- (BOOL)mouseHandlerReportingAllowed:(PTYMouseHandler *)handler {
    return [self.delegate xtermMouseReporting];
}

- (void)mouseHandlerLockScrolling:(PTYMouseHandler *)handler {
    // Lock auto scrolling while the user is selecting text, but not for a first-mouse event
    // because drags are ignored for those.
    [self lockScroll];
}

- (void)mouseHandlerDidMutateState:(PTYMouseHandler *)handler {
    // Make changes to selection appear right away.
    [self requestDelegateRedraw];
}

- (void)mouseHandlerDidInferScrollingIntent:(PTYMouseHandler *)handler trying:(BOOL)trying {
    [_delegate textViewThinksUserIsTryingToSendArrowKeysWithScrollWheel:trying];
}

- (void)mouseHandlerOpenTargetWithEvent:(NSEvent *)event
                           inBackground:(BOOL)inBackground {
    [_urlActionHelper openTargetWithEvent:event inBackground:inBackground];
}

- (BOOL)mouseHandlerIsScrolledToBottom:(PTYMouseHandler *)handler {
    return [self scrolledToBottom];
}

- (void)mouseHandlerUnlockScrolling:(PTYMouseHandler *)handler {
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:NO];
}

- (VT100GridCoord)mouseHandlerCoordForPointInWindow:(NSPoint)point {
    return [self coordForPointInWindow:point];
}

- (VT100GridCoord)mouseHandlerCoordForPointInView:(NSPoint)point {
    NSRect liveRect = [self liveRect];
    VT100GridCoord coord = VT100GridCoordMake((point.x - liveRect.origin.x) / _charWidth,
                                              (point.y - liveRect.origin.y) / _lineHeight);
    coord.x = MAX(0, coord.x);
    coord.y = MAX(0, coord.y);
    return coord;
}

- (NSPoint)mouseHandlerReportablePointForPointInView:(NSPoint)point {
    NSRect liveRect = [self liveRect];
    const NSPoint limit = NSMakePoint(_charWidth * self.dataSource.width - 1,
                                      _lineHeight * self.dataSource.height - 1);
    return NSMakePoint(MAX(0, MIN(limit.x, point.x - liveRect.origin.x)),
                       MAX(0, MIN(limit.y, point.y - liveRect.origin.y)));

}

- (BOOL)mouseHandlerCanWriteToTTY:(PTYMouseHandler *)handler {
    return [self.delegate textViewCanWriteToTTY];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)handler viewCoordIsReportable:(NSPoint)point {
    const NSRect liveRect = [self liveRect];
    DLog(@"Point in view is %@, live rect is %@", NSStringFromPoint(point), NSStringFromRect(liveRect));
    return NSPointInRect(point, liveRect);
}

- (void)mouseHandlerMoveCursorToCoord:(VT100GridCoord)coord
                             forEvent:(NSEvent *)event {
    BOOL verticalOk;
    if ([_delegate textViewShouldPlaceCursorAt:coord verticalOk:&verticalOk]) {
        [self placeCursorOnCurrentLineWithEvent:event verticalOk:verticalOk];
    }
}

- (void)mouseHandlerSetFindOnPageCursorCoord:(VT100GridCoord)clickPoint {
    VT100GridAbsCoord absCoord =
    VT100GridAbsCoordMake(clickPoint.x,
                          [_dataSource totalScrollbackOverflow] + clickPoint.y);
    [_findOnPageHelper setStartPoint:absCoord];
}

- (BOOL)mouseHandlerAtPasswordPrompt:(PTYMouseHandler *)handler {
    return _delegate.textViewPasswordInput;
}

- (VT100GridCoord)mouseHandlerCursorCoord:(PTYMouseHandler *)handler {
    return VT100GridCoordMake([_dataSource cursorX] - 1,
                              [_dataSource numberOfLines] - [_dataSource height] + [_dataSource cursorY] - 1);
}

- (void)mouseHandlerOpenPasswordManager:(PTYMouseHandler *)handler {
    [_delegate textViewDidSelectPasswordPrompt];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)handler
 getFindOnPageCursor:(VT100GridCoord *)coord {
    if (_findOnPageHelper.findCursor.type != FindCursorTypeCoord) {
        return NO;
    }
    const VT100GridAbsCoord findOnPageCursor = _findOnPageHelper.findCursor.coord;
    *coord = VT100GridCoordMake(findOnPageCursor.x,
                                findOnPageCursor.y -
                                [_dataSource totalScrollbackOverflow]);
    return YES;
}

- (void)mouseHandlerResetFindOnPageCursor:(PTYMouseHandler *)handler {
    [_findOnPageHelper resetFindCursor];
}

- (BOOL)mouseHandlerIsValid:(PTYMouseHandler *)handler {
    return _delegate != nil;
}

- (void)mouseHandlerCopy:(PTYMouseHandler *)handler {
    [self copySelectionAccordingToUserPreferences];
}

- (BOOL)mouseHandlerAnyReportingModeEnabled:(PTYMouseHandler *)handler {
    return [_delegate textViewAnyMouseReportingModeIsEnabled];
}

- (NSPoint)mouseHandler:(PTYMouseHandler *)handler
      viewCoordForEvent:(NSEvent *)event
                clipped:(BOOL)clipped {
    if (!clipped) {
        return [self pointForEvent:event];
    }
    return [self locationInTextViewFromEvent:event];
}

- (void)mouseHandler:(PTYMouseHandler *)handler sendFakeOtherMouseUp:(NSEvent *)event {
    [self otherMouseUp:event];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)handler
    reportMouseEvent:(NSEventType)eventType
           modifiers:(NSUInteger)modifiers
              button:(MouseButtonNumber)button
          coordinate:(VT100GridCoord)coord
               point:(NSPoint)point
              event:(NSEvent *)event
               delta:(CGSize)delta
allowDragBeforeMouseDown:(BOOL)allowDragBeforeMouseDown
            testOnly:(BOOL)testOnly {
    return [_delegate textViewReportMouseEvent:eventType
                                     modifiers:modifiers
                                        button:button
                                    coordinate:coord
                                         point:point
                                         delta:delta
                      allowDragBeforeMouseDown:allowDragBeforeMouseDown
                                      testOnly:testOnly];
}

- (BOOL)mouseHandlerViewIsFirstResponder:(PTYMouseHandler *)mouseHandler {
    return [_delegate textViewOrComposerIsFirstResponder];
}

- (BOOL)mouseHandlerShouldReportClicksAndDrags:(PTYMouseHandler *)mouseHandler {
    return [[self delegate] xtermMouseReportingAllowClicksAndDrags];
}

- (BOOL)mouseHandlerShouldReportScroll:(PTYMouseHandler *)mouseHandler {
    return [[self delegate] xtermMouseReportingAllowMouseWheel];
}

- (void)mouseHandlerJiggle:(PTYMouseHandler *)mouseHandler {
    [self scrollLineUp:nil];
    [self scrollLineDown:nil];
}

- (CGFloat)mouseHandler:(PTYMouseHandler *)mouseHandler accumulateScrollFromEvent:(NSEvent *)event {
    PTYScrollView *scrollView = (PTYScrollView *)self.enclosingScrollView;
    if (event.it_isVerticalScroll) {
        return [self scrollDeltaYAdjustedForMouseReporting:[scrollView accumulateVerticalScrollFromEvent:event]];
    }

    // Horizontal scroll
    CGFloat delta;
    if ([iTermAdvancedSettingsModel useModernScrollWheelAccumulator]) {
        delta = [_horizontalScrollAccumulator deltaForEvent:event increment:self.charWidth];
    } else {
        delta = [_horizontalScrollAccumulator legacyDeltaForEvent:event increment:self.charWidth];
    }
    return [self scrollDeltaXAdjustedForMouseReporting:delta];
}

- (void)mouseHandler:(PTYMouseHandler *)handler
          sendString:(NSString *)stringToSend
              latin1:(BOOL)forceLatin1 {
    if (forceLatin1) {
        [_delegate writeStringWithLatin1Encoding:stringToSend];
    } else {
        [_delegate writeTask:stringToSend];
    }
}

- (void)mouseHandlerRemoveSelection:(PTYMouseHandler *)mouseHandler {
    [self deselect];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)mouseHandler moveSelectionToPointInEvent:(NSEvent *)event {
    const NSPoint locationInTextView = [self locationInTextViewFromEvent:event];
    const NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
    const int x = clickPoint.x;
    const int y = clickPoint.y;
    DLog(@"Update live selection during SCROLL");
    return [self moveSelectionEndpointToX:x Y:y locationInTextView:locationInTextView];
}

- (BOOL)mouseHandler:(PTYMouseHandler *)mouseHandler moveSelectionToGridCoord:(VT100GridCoord)coord
           viewCoord:(NSPoint)locationInTextView {
    return [self moveSelectionEndpointToX:coord.x
                                        Y:coord.y
                       locationInTextView:locationInTextView];
}

- (NSString *)mouseHandler:(PTYMouseHandler *)mouseHandler
        stringForUpOrRight:(BOOL)upOrRight  // if NO, then down/left
                  vertical:(BOOL)vertical
                     flags:(NSEventModifierFlags)flags
                    latin1:(out BOOL *)forceLatin1 {
    const BOOL downOrLeft = !upOrRight;

    BOOL verticalOnly = NO;
    if ([self mouseHandlerAlternateScrollModeIsEnabled:mouseHandler verticalOnly:&verticalOnly]) {
        *forceLatin1 = YES;
        NSData *data;
        if (vertical) {
            data = downOrLeft ? [_dataSource.terminalOutput keyArrowDown:flags] :
            [_dataSource.terminalOutput keyArrowUp:flags];
        } else {
            if (verticalOnly) {
                return nil;
            }
            data = downOrLeft ? [_dataSource.terminalOutput keyArrowRight:flags] : [_dataSource.terminalOutput keyArrowLeft:flags];
        }
        return [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    } else {
        *forceLatin1 = NO;
        if (!vertical) {
            // Legacy code path not supported
            return @"";
        }
        NSString *string = downOrLeft ? [iTermAdvancedSettingsModel alternateMouseScrollStringForDown] :
                                  [iTermAdvancedSettingsModel alternateMouseScrollStringForUp];
        return [string stringByExpandingVimSpecialCharacters];
    }
}

- (BOOL)mouseHandlerAlternateScrollModeIsEnabled:(PTYMouseHandler *)handler
                                    verticalOnly:(out BOOL *)verticalOnly {
    if ([iTermAdvancedSettingsModel alternateMouseScroll]) {
        DLog(@"Alternate mouse scroll on because of advanced setting having a non-default value");
        *verticalOnly = NO;
        return YES;
    }
    if ([self.delegate textViewAlternateMouseScroll:verticalOnly]) {
        return YES;
    }
    return self.dataSource.terminalAlternateScrollMode;
}

- (BOOL)mouseHandlerShowingAlternateScreen:(PTYMouseHandler *)mouseHandler {
    return self.dataSource.terminalSoftAlternateScreenMode;
}

- (void)mouseHandlerWillDrag:(PTYMouseHandler *)mouseHandler {
    [self removeUnderline];
}

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
           dragImage:(id<iTermImageInfoReading>)image
            forEvent:(NSEvent *)event {
    [self _dragImage:image forEvent:event];
}

- (NSString *)mouseHandlerSelectedText:(PTYMouseHandler *)mouseHandler {
    return [self selectedText];
}

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
            dragText:(NSString *)text
            forEvent:(NSEvent *)event {
    [self _dragText:text forEvent:event];
}

- (void)mouseHandler:(PTYMouseHandler *)mouseHandler
dragSemanticHistoryWithEvent:(NSEvent *)event
               coord:(VT100GridCoord)coord {
    [self handleSemanticHistoryItemDragWithEvent:event coord:coord];
}

- (id<iTermSwipeHandler>)mouseHandlerSwipeHandler:(PTYMouseHandler *)sender {
    return [self.delegate textViewSwipeHandler];
}

- (CGSize)scrollDeltaAdjustedForMouseReporting:(CGSize)delta {
    if (fabs(delta.width) > fabs(delta.height)) {
        return CGSizeMake([self scrollDeltaXAdjustedForMouseReporting:delta.width], 0);
    }
    return CGSizeMake(0, [self scrollDeltaYAdjustedForMouseReporting:delta.height]);
}

- (CGFloat)scrollDeltaYAdjustedForMouseReporting:(CGFloat)deltaY {
    return [self scrollDeltaWithUnit:self.enclosingScrollView.verticalLineScroll
                               delta:deltaY];
}

- (CGFloat)scrollDeltaXAdjustedForMouseReporting:(CGFloat)deltaX {
    return [self scrollDeltaWithUnit:self.charWidth delta:deltaX];
}

- (CGFloat)scrollDeltaWithUnit:(CGFloat)unit delta:(CGFloat)delta {
    if (![iTermAdvancedSettingsModel fastTrackpad]) {
        return delta;
    }
    // This value is used for mouse reporting and we need to report lines, not pixels.
    const CGFloat frac = delta / unit;
    if (frac < 0) {
        return floor(frac);
    }
    return ceil(frac);
}

- (CGSize)mouseHandlerAccumulatedDelta:(PTYMouseHandler *)sender
                              forEvent:(NSEvent *)event {
    CGSize delta = { 0 };
    if (event.type != NSEventTypeScrollWheel) {
        return delta;
    }
    if (event.it_isVerticalScroll) {
        delta.height = [_scrollAccumulator deltaForEvent:event
                                               increment:self.enclosingScrollView.verticalLineScroll];
    } else {
        delta.width = [_horizontalScrollAccumulator deltaForEvent:event
                                                        increment:self.charWidth];
    }
    return [self scrollDeltaAdjustedForMouseReporting:delta];
}

- (long long)mouseHandlerTotalScrollbackOverflow:(nonnull PTYMouseHandler *)sender {
    return _dataSource.totalScrollbackOverflow;
}

- (void)mouseHandlerSetClickCoord:(VT100GridCoord)coord
                           button:(NSInteger)button
                            count:(NSInteger)count
                        modifiers:(NSEventModifierFlags)modifiers
                      sideEffects:(iTermClickSideEffects)sideEffects
                            state:(iTermMouseState)state {
    const long long overflow = _dataSource.totalScrollbackOverflow;
    [self.delegate textViewSetClickCoord:VT100GridAbsCoordFromCoord(coord, overflow)
                                  button:button
                                   count:count
                               modifiers:modifiers
                             sideEffects:sideEffects
                                   state:state];
}

- (void)mouseHandlerRedraw:(PTYMouseHandler *)mouseHandler {
    [self requestDelegateRedraw];
}

- (NSString *)mouseHandler:(PTYMouseHandler *)mouseHandler
             blockIDOnLine:(int)line {
    if (line < 0) {
        return nil;
    }
    BOOL changed = NO;
    NSString *blockID = [self updateHoverButtonsForLine:line changed:&changed];
    if (changed) {
        DLog(@"request delegate redraw");
        [self.delegate textViewUpdateTrackingAreas];
        [self requestDelegateRedraw];
    } else {
        DLog(@"no change");
    }
    return blockID;
}

// Return yes to short-circuit
- (BOOL)mouseHandlerMouseDownAt:(NSPoint)locationInWindow {
    NSPoint point = [self convertPoint:locationInWindow fromView:nil];
    DLog(@"TextView handling mouseDown at %@", NSStringFromPoint(point));
    if (!NSPointInRect(point, self.bounds)) {
        DLog(@"TextView handling mouseDown: not in bounds");
        return NO;
    }
    if (@available(macOS 11, *)) {
        for (iTermTerminalButton *button in self.terminalButtons) {
            if (NSPointInRect(point, button.desiredFrame)) {
                if ([button mouseDownInside]) {
                    [self requestDelegateRedraw];
                }
                return YES;
            }
            DLog(@"TextView handling mouseDown: not in %@ with frame %@", button.description, NSStringFromRect(button.desiredFrame));
        }
    }
    DLog(@"TextView handling mouseDown: not in anything");
    return NO;
}

- (BOOL)mouseHandlerMouseUp:(NSEvent *)event {
    DLog(@"mouseUp: mouseHandlerMouseUp");
    if (event.clickCount != 1) {
        DLog(@"mouseUp: not a single click");
        [self.delegate textViewRemoveSelectedCommand];
        return NO;
    }
    const NSPoint locationInWindow = event.locationInWindow;
    NSPoint point = [self convertPoint:locationInWindow fromView:nil];
    if (!NSPointInRect(point, self.bounds)) {
        DLog(@"mouseUp: not in bounds");
        return NO;

    }
    BOOL clicked = NO;
    if (@available(macOS 11, *)) {
        [self updateButtonHover:locationInWindow pressed:NO];
        for (iTermTerminalButton *button in self.terminalButtons) {
            if (!button.pressed) {
                DLog(@"mouseUp: %@ not pressed", button.description);
                continue;
            }
            clicked = clicked || button.pressed;
            if ([button mouseUpWithLocationInWindow:locationInWindow]) {
                [self requestDelegateRedraw];
            }
        }
    }
    return clicked;
}

#pragma mark - iTermSecureInputRequesting

- (BOOL)isRequestingSecureInput {
    return [self.delegate textViewPasswordInput];
}

#pragma mark - iTermFocusFollowsMouseDelegate

- (void)focusFollowsMouseDidBecomeFirstResponder {
    [self.delegate textViewDidBecomeFirstResponder];
}

- (NSResponder *)focusFollowsMouseDesiredFirstResponder {
    return self;
}

- (void)focusFollowsMouseDidChangeMouseLocationToRefusFirstResponderAt {
    [self.delegate textViewUpdateTrackingAreas];
}

@end

@implementation PTYTextView(PointerDelegate)
- (void)pasteFromClipboardWithEvent:(NSEvent *)event {
    [self paste:nil];
}

- (void)pasteFromSelectionWithEvent:(NSEvent *)event {
    [self pasteSelection:nil];
}

- (void)openTargetWithEvent:(NSEvent *)event {
    [_urlActionHelper openTargetWithEvent:event inBackground:NO];
}

- (void)openTargetInBackgroundWithEvent:(NSEvent *)event {
    [_urlActionHelper openTargetWithEvent:event inBackground:YES];
}

- (void)smartSelectAndMaybeCopyWithEvent:(NSEvent *)event
                        ignoringNewlines:(BOOL)ignoringNewlines {
    [_selection endLiveSelection];
    [_urlActionHelper smartSelectAndMaybeCopyWithEvent:event
                                      ignoringNewlines:ignoringNewlines];
}

// Called for a right click that isn't control+click (e.g., two fingers on trackpad).
- (void)openContextMenuWithEvent:(NSEvent *)event {
    if ([self showCommandInfoForEvent:event]) {
        return;
    }

    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    [_contextMenuHelper openContextMenuAt:VT100GridCoordMake(clickPoint.x, clickPoint.y)
                                    event:event];
}

- (void)extendSelectionWithEvent:(NSEvent *)event {
    if (![_selection hasSelection]) {
        return;
    }
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
    const long long overflow = _dataSource.totalScrollbackOverflow;
    [_selection beginExtendingSelectionAt:VT100GridAbsCoordMake(clickPoint.x, clickPoint.y + overflow)];
    [_selection endLiveSelection];
    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (void)quickLookWithEvent:(NSEvent *)event {
    [self handleQuickLookWithEvent:event];
}

- (void)nextTabWithEvent:(NSEvent *)event {
    [_delegate textViewSelectNextTab];
}

- (void)previousTabWithEvent:(NSEvent *)event {
    [_delegate textViewSelectPreviousTab];
}

- (void)nextWindowWithEvent:(NSEvent *)event {
    [_delegate textViewSelectNextWindow];
}

- (void)previousWindowWithEvent:(NSEvent *)event {
    [_delegate textViewSelectPreviousWindow];
}

- (void)movePaneWithEvent:(NSEvent *)event {
    [self movePane:nil];
}

- (void)sendEscapeSequence:(NSString *)text withEvent:(NSEvent *)event {
    [_delegate sendEscapeSequence:text];
}

- (void)sendHexCode:(NSString *)codes withEvent:(NSEvent *)event {
    [_delegate sendHexCode:codes];
}

- (void)sendText:(NSString *)text withEvent:(NSEvent *)event escaping:(iTermSendTextEscaping)escaping {
    [_delegate sendText:text escaping:escaping];
}

- (void)selectPaneLeftWithEvent:(NSEvent *)event {
    [_delegate selectPaneLeftInCurrentTerminal];
}

- (void)selectPaneRightWithEvent:(NSEvent *)event {
    [_delegate selectPaneRightInCurrentTerminal];
}

- (void)selectPaneAboveWithEvent:(NSEvent *)event {
    [_delegate selectPaneAboveInCurrentTerminal];
}

- (void)selectPaneBelowWithEvent:(NSEvent *)event {
    [_delegate selectPaneBelowInCurrentTerminal];
}

- (void)newWindowWithProfile:(NSString *)guid withEvent:(NSEvent *)event {
    [_delegate textViewCreateWindowWithProfileGuid:guid];
}

- (void)newTabWithProfile:(NSString *)guid withEvent:(NSEvent *)event {
    [_delegate textViewCreateTabWithProfileGuid:guid];
}

- (void)newVerticalSplitWithProfile:(NSString *)guid withEvent:(NSEvent *)event {
    [_delegate textViewSplitVertically:YES withProfileGuid:guid];
}

- (void)newHorizontalSplitWithProfile:(NSString *)guid withEvent:(NSEvent *)event {
    [_delegate textViewSplitVertically:NO withProfileGuid:guid];
}

- (void)selectNextPaneWithEvent:(NSEvent *)event {
    [_delegate textViewSelectNextPane];
}

- (void)selectPreviousPaneWithEvent:(NSEvent *)event {
    [_delegate textViewSelectPreviousPane];
}

- (void)selectMenuItemWithIdentifier:(NSString *)identifier
                               title:(NSString *)title
                               event:(NSEvent *)event {
    [_delegate textViewSelectMenuItemWithIdentifier:identifier title:title];
}

- (void)advancedPasteWithConfiguration:(NSString *)configuration
                             fromSelection:(BOOL)fromSelection
                             withEvent:(NSEvent *)event {
    [self.delegate textViewPasteSpecialWithStringConfiguration:configuration
                                                 fromSelection:fromSelection];
}

- (void)invokeScriptFunction:(NSString *)function withEvent:(NSEvent *)event {
    [self.delegate textViewInvokeScriptFunction:function];
}

@end
