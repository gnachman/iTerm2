#import "PTYTextView.h"

#import "charmaps.h"
#import "FileTransferManager.h"
#import "FontSizeEstimator.h"
#import "FutureMethods.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermAltScreenMouseScrollInferer.h"
#import "iTermBadgeLabel.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermCPS.h"
#import "iTermExpose.h"
#import "iTermFindCursorView.h"
#import "iTermFindOnPageHelper.h"
#import "iTermImageInfo.h"
#import "iTermLaunchServices.h"
#import "iTermLocalHostNameGuesser.h"
#import "iTermMouseCursor.h"
#import "iTermNSKeyBindingEmulator.h"
#import "iTermPreferences.h"
#import "iTermPrintAccessoryViewController.h"
#import "iTermQuickLookController.h"
#import "iTermScrollAccumulator.h"
#import "iTermSelection.h"
#import "iTermSelectionScrollHelper.h"
#import "iTermShellHistoryController.h"
#import "iTermTextDrawingHelper.h"
#import "iTermTextExtractor.h"
#import "iTermTextViewAccessibilityHelper.h"
#import "iTermURLActionFactory.h"
#import "iTermURLStore.h"
#import "iTermWebViewWrapperViewController.h"
#import "iTermWarning.h"
#import "MovePaneController.h"
#import "MovingAverage.h"
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
#import "NSSavePanel+iTerm.h"
#import "NSResponder+iTerm.h"
#import "NSSavePanel+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "NSWindow+PSM.h"
#import "PasteboardHistory.h"
#import "PointerController.h"
#import "PointerPrefsController.h"
#import "PreferencePanel.h"
#import "PTYNoteView.h"
#import "PTYNoteViewController.h"
#import "PTYScrollView.h"
#import "PTYTab.h"
#import "PTYTask.h"
#import "RegexKitLite.h"
#import "SCPPath.h"
#import "SearchResult.h"
#import "SmartMatch.h"
#import "SmartSelectionController.h"
#import "SolidColorView.h"
#import "ThreeFingerTapGestureRecognizer.h"
#import "URLAction.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"
#import "WindowControllerInterface.h"

#import <CoreServices/CoreServices.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <sys/time.h>

#import <WebKit/WebKit.h>

static const int kMaxSelectedTextLengthForCustomActions = 400;

static const NSUInteger kDragPaneModifiers = (NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift);
static const NSUInteger kRectangularSelectionModifiers = (NSEventModifierFlagCommand | NSEventModifierFlagOption);
static const NSUInteger kRectangularSelectionModifierMask = (kRectangularSelectionModifiers | NSEventModifierFlagControl);

static PTYTextView *gCurrentKeyEventTextView;  // See comment in -keyDown:

// Minimum distance that the mouse must move before a cmd+drag will be
// recognized as a drag.
static const int kDragThreshold = 3;

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

@interface PTYTextView () <
    iTermAltScreenMouseScrollInfererDelegate,
    iTermTextViewAccessibilityHelperDelegate,
    iTermFindCursorViewDelegate,
    iTermFindOnPageHelperDelegate,
    iTermSelectionDelegate,
    iTermSelectionScrollHelperDelegate,
    NSDraggingSource,
    NSMenuDelegate,
    NSPopoverDelegate>

@property(nonatomic, retain) iTermSelection *selection;
@property(nonatomic, retain) iTermSemanticHistoryController *semanticHistoryController;
@property(nonatomic, retain) iTermFindCursorView *findCursorView;
@property(nonatomic, retain) NSWindow *findCursorWindow;  // For find-cursor animation
@property(nonatomic, retain) iTermQuickLookController *quickLookController;
@property(strong, readwrite, nullable) NSTouchBar *touchBar NS_AVAILABLE_MAC(10_12_2);

// Set when a context menu opens, nilled when it closes. If the data source changes between when we
// ask the context menu to open and when the main thread enters a tracking runloop, the text under
// the selection can change. We want to respect what we show while the context menu is open.
// See issue 4048.
@property(nonatomic, copy) NSString *savedSelectedText;
@end

@implementation PTYTextView {
    // -refresh does not want to be reentrant.
    BOOL _inRefresh;

    // geometry
    double _lineHeight;
    double _charWidth;

    // NSTextInputClient support

    // When an event is passed to -handleEvent, it may get dispatched to -insertText:replacementRange:
    // or -doCommandBySelector:. If one of these methods processes the input by sending it to the
    // delegate then this will be set to YES to prevent it from being handled twice.
    BOOL _keyPressHandled;

    // This is used by the experimental feature guarded by [iTermAdvancedSettingsModel experimentalKeyHandling].
    // Indicates if marked text existed before invoking -handleEvent: for a keypress. If the
    // input method handles the keypress and causes the IME to finish then the keypress must not
    // be passed to the delegate. -insertText:replacementRange: and -doCommandBySelector: need to
    // know if marked text existed prior to -handleEvent so they can avoid passing the event to the
    // delegate in this case.
    BOOL _hadMarkedTextBeforeHandlingKeypressEvent;

    NSDictionary *_markedTextAttributes;

    BOOL _mouseDown;
    BOOL _mouseDragged;
    BOOL _mouseDownOnSelection;
    BOOL _mouseDownOnImage;
    iTermImageInfo *_imageBeingClickedOn;
    NSEvent *_mouseDownEvent;

    // blinking cursor
    NSTimeInterval _timeOfLastBlink;

    // Was the last pressed key a "repeat" where the key is held down?
    BOOL _keyIsARepeat;

    // Previous tracking rect to avoid expensive calls to addTrackingRect.
    NSRect _trackingRect;

    // Helps with "selection scroll"
    iTermSelectionScrollHelper *_selectionScrollHelper;

    // Helps drawing text and background.
    iTermTextDrawingHelper *_drawingHelper;

    // Last position that accessibility was read up to.
    int _lastAccessibilityCursorX;
    int _lastAccessibiltyAbsoluteCursorY;

    BOOL _changedSinceLastExpose;

    // Works around an apparent OS bug where we get drag events without a mousedown.
    BOOL dragOk_;

    // Flag to make sure a Semantic History drag check is only one once per drag
    BOOL _semanticHistoryDragged;

    // Saves the monotonically increasing event number of a first-mouse click, which disallows
    // selection.
    NSInteger _firstMouseEventNumber;

    // Number of fingers currently down (only valid if three finger click
    // emulates middle button)
    int _numTouches;

    // If true, ignore the next mouse up because it's due to a three finger
    // mouseDown.
    BOOL _mouseDownIsThreeFingerClick;

    PointerController *pointer_;
    NSCursor *cursor_;

    // True while the context menu is being opened.
    BOOL openingContextMenu_;

    // Detects three finger taps (as opposed to clicks).
    ThreeFingerTapGestureRecognizer *threeFingerTapGestureRecognizer_;

    // Position of cursor last time we looked. Since the cursor might move around a lot between
    // calls to -updateDirtyRects without making any changes, we only redraw the old and new cursor
    // positions.
    VT100GridAbsCoord _previousCursorCoord;

    // Point clicked, valid only during -validateMenuItem and calls made from
    // the context menu and if x and y are nonnegative.
    VT100GridCoord _validationClickPoint;

    iTermSelection *_oldSelection;

    // The most recent mouse-down was a "first mouse" (activated the window).
    BOOL _mouseDownWasFirstMouse;

    // Size of the documentVisibleRect when the badge was set.
    NSSize _badgeDocumentVisibleRectSize;

    // Show a background indicator when in broadcast input mode
    BOOL _showStripesWhenBroadcastingInput;

    iTermFindOnPageHelper *_findOnPageHelper;
    iTermTextViewAccessibilityHelper *_accessibilityHelper;
    iTermBadgeLabel *_badgeLabel;

    NSPoint _mouseLocationToRefuseFirstResponderAt;

    iTermNSKeyBindingEmulator *_keyBindingEmulator;

    // Detects when the user is trying to scroll in alt screen with the scroll wheel.
    iTermAltScreenMouseScrollInferer *_altScreenMouseScrollInferer;

    NSEvent *_eventBeingHandled;

    NSMutableArray<iTermHighlightedRow *> *_highlightedRows;

    // Used to report scroll wheel mouse events.
    iTermScrollAccumulator *_scrollAccumulator;

    BOOL _haveSeenScrollWheelEvent;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
    // Must call initWithFrame:colorMap:.
    assert(false);
}

- (instancetype)initWithFrame:(NSRect)aRect colorMap:(iTermColorMap *)colorMap {
    self = [super initWithFrame:aRect];
    if (self) {
        [self resetMouseLocationToRefuseFirstResponderAt];
        _drawingHelper = [[iTermTextDrawingHelper alloc] init];
        _drawingHelper.delegate = self;

        _colorMap = [colorMap retain];
        _colorMap.delegate = self;

        _drawingHelper.colorMap = colorMap;

        _firstMouseEventNumber = -1;

        [self updateMarkedTextAttributes];
        _drawingHelper.cursorVisible = YES;
        _selection = [[iTermSelection alloc] init];
        _selection.delegate = self;
        _oldSelection = [_selection copy];
        _drawingHelper.underlinedRange =
            VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
        _timeOfLastBlink = [NSDate timeIntervalSinceReferenceDate];

        // register for drag and drop
        [self registerForDraggedTypes: [NSArray arrayWithObjects:
            NSFilenamesPboardType,
            NSStringPboardType,
            nil]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(useBackgroundIndicatorChanged:)
                                                     name:kUseBackgroundPatternIndicatorChangedNotification
                                                   object:nil];
        [self useBackgroundIndicatorChanged:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_settingsChanged:)
                                                     name:kRefreshTerminalNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_pointerSettingsChanged:)
                                                     name:kPointerPrefsChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(imageDidLoad:)
                                                     name:iTermImageDidLoad
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];

        _semanticHistoryController = [[iTermSemanticHistoryController alloc] init];
        _semanticHistoryController.delegate = self;
        _semanticHistoryDragged = NO;

        pointer_ = [[PointerController alloc] init];
        pointer_.delegate = self;
        _primaryFont = [[PTYFontInfo alloc] init];
        _secondaryFont = [[PTYFontInfo alloc] init];

        if ([pointer_ viewShouldTrackTouches]) {
            DLog(@"Begin tracking touches in view %@", self);
            [self setAcceptsTouchEvents:YES];
            [self setWantsRestingTouches:YES];
            if ([self useThreeFingerTapGestureRecognizer]) {
                threeFingerTapGestureRecognizer_ =
                    [[ThreeFingerTapGestureRecognizer alloc] initWithTarget:self
                                                                   selector:@selector(threeFingerTap:)];
            }
        }
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
        _keyBindingEmulator = [[iTermNSKeyBindingEmulator alloc] init];

        _altScreenMouseScrollInferer = [[iTermAltScreenMouseScrollInferer alloc] init];
        _altScreenMouseScrollInferer.delegate = self;
        [self refuseFirstResponderAtCurrentMouseLocation];

        _scrollAccumulator = [[iTermScrollAccumulator alloc] init];
    }
    return self;
}

// For Metal
- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
    if (needsDisplay) {
        [_delegate textViewNeedsDisplayInRect:self.bounds];
    }
}

// For Metal
- (void)setNeedsDisplayInRect:(NSRect)invalidRect {
    [super setNeedsDisplayInRect:invalidRect];
    [_delegate textViewNeedsDisplayInRect:invalidRect];
}

- (void)removeAllTrackingAreas {
    while (self.trackingAreas.count) {
        [self removeTrackingArea:self.trackingAreas[0]];
    }
}

- (void)dealloc {
    [_selection release];
    [_oldSelection release];
    [_smartSelectionRules release];

    [_mouseDownEvent release];
    _mouseDownEvent = nil;

    [self removeAllTrackingAreas];
    if ([self isFindingCursor]) {
        [self.findCursorWindow close];
    }
    [_findCursorWindow release];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _colorMap.delegate = nil;
    [_colorMap release];

    [_primaryFont release];
    [_secondaryFont release];

    [_markedTextAttributes release];

    [_semanticHistoryController release];

    [pointer_ release];
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
    [_savedSelectedText release];
    [_keyBindingEmulator release];
    [_altScreenMouseScrollInferer release];
    [_highlightedRows release];
    [_scrollAccumulator release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<PTYTextView: %p frame=%@ visibleRect=%@ dataSource=%@ delegate=%@ window=%@>",
            self,
            [NSValue valueWithRect:self.frame],
            [NSValue valueWithRect:[self visibleRect]],
            _dataSource,
            _delegate,
            self.window];
}

- (BOOL)useThreeFingerTapGestureRecognizer {
    // This used to be guarded by [[NSUserDefaults standardUserDefaults] boolForKey:@"ThreeFingerTapEmulatesThreeFingerClick"];
    // but I'm going to turn it on by default and see if anyone complains. 12/16/13
    return YES;
}

- (void)viewDidChangeBackingProperties {
    CGFloat scale = [[[self window] screen] backingScaleFactor];
    BOOL isRetina = scale > 1;
    _drawingHelper.antiAliasedShift = isRetina ? 0.5 : 0;
    _drawingHelper.isRetina = isRetina;
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

- (NSColor *)selectionBackgroundColor {
    CGFloat alpha = [self useTransparency] ? 1 - _transparency : 1;
    return [[_colorMap processedBackgroundColorForBackgroundColor:[_colorMap colorForKey:kColorMapSelection]] colorWithAlphaComponent:alpha];
}

- (NSColor *)selectedTextColor {
    return [_colorMap processedTextColorForTextColor:[_colorMap colorForKey:kColorMapSelectedText]
                                 overBackgroundColor:[self selectionBackgroundColor]
                              disableMinimumContrast:NO];
}

- (void)updateMarkedTextAttributes {
    // During initialization, this may be called before the non-ascii font is set so we use a system
    // font as a placeholder.
    NSDictionary *theAttributes =
        @{ NSBackgroundColorAttributeName: [self defaultBackgroundColor] ?: [NSColor blackColor],
           NSForegroundColorAttributeName: [self defaultTextColor] ?: [NSColor whiteColor],
           NSFontAttributeName: self.nonAsciiFont ?: [NSFont systemFontOfSize:12],
           NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle | NSUnderlineByWord) };

    [self setMarkedTextAttributes:theAttributes];
}

- (void)sendFakeThreeFingerClickDown:(BOOL)isDown basedOnEvent:(NSEvent *)event {
    NSEvent *fakeEvent = isDown ? [event mouseDownEventFromGesture] : [event mouseUpEventFromGesture];

    int saved = _numTouches;
    _numTouches = 3;
    if (isDown) {
        DLog(@"Emulate three finger click down");
        [self mouseDown:fakeEvent];
        DLog(@"Returned from mouseDown");
    } else {
        DLog(@"Emulate three finger click up");
        [self mouseUp:fakeEvent];
        DLog(@"Returned from mouseDown");
    }
    DLog(@"Restore numTouches to saved value of %d", saved);
    _numTouches = saved;
}

- (void)threeFingerTap:(NSEvent *)ev {
    [self sendFakeThreeFingerClickDown:YES basedOnEvent:ev];
    [self sendFakeThreeFingerClickDown:NO basedOnEvent:ev];
}

- (void)touchesBeganWithEvent:(NSEvent *)ev {
    _numTouches = [[ev touchesMatchingPhase:NSTouchPhaseBegan | NSTouchPhaseStationary
                                           inView:self] count];
    [threeFingerTapGestureRecognizer_ touchesBeganWithEvent:ev];
    DLog(@"%@ Begin touch. numTouches_ -> %d", self, _numTouches);
}

- (void)touchesEndedWithEvent:(NSEvent *)ev {
    _numTouches = [[ev touchesMatchingPhase:NSTouchPhaseStationary
                                     inView:self] count];
    [threeFingerTapGestureRecognizer_ touchesEndedWithEvent:ev];
    DLog(@"%@ End touch. numTouches_ -> %d", self, _numTouches);
}

- (void)touchesCancelledWithEvent:(NSEvent *)event {
    _numTouches = 0;
    [threeFingerTapGestureRecognizer_ touchesCancelledWithEvent:event];
    DLog(@"%@ Cancel touch. numTouches_ -> %d", self, _numTouches);
}

- (void)refuseFirstResponderAtCurrentMouseLocation {
    DLog(@"set refuse location");
    _mouseLocationToRefuseFirstResponderAt = [NSEvent mouseLocation];
}

- (void)resetMouseLocationToRefuseFirstResponderAt {
    DLog(@"reset refuse location from\n%@", [NSThread callStackSymbols]);
    _mouseLocationToRefuseFirstResponderAt = NSMakePoint(DBL_MAX, DBL_MAX);
}

- (BOOL)resignFirstResponder {
    if (!self.it_shouldIgnoreFirstResponderChanges) {
        [_altScreenMouseScrollInferer firstResponderDidChange];
        [self removeUnderline];
        [self placeFindCursorOnAutoHide];
        DLog(@"resignFirstResponder %@", self);
        DLog(@"%@", [NSThread callStackSymbols]);
    } else {
        DLog(@"%@ ignoring first responder changes in resignFirstResponder", self);
    }
    return YES;
}

- (BOOL)becomeFirstResponder {
    if (!self.it_shouldIgnoreFirstResponderChanges) {
        [_altScreenMouseScrollInferer firstResponderDidChange];
        [_delegate textViewDidBecomeFirstResponder];
        DLog(@"becomeFirstResponder %@", self);
        DLog(@"%@", [NSThread callStackSymbols]);
    } else {
        DLog(@"%@ ignoring first responder changes in becomeFirstResponder", self);
    }
    return YES;
}

- (void)viewWillMoveToWindow:(NSWindow *)win {
    if (!win && [self window]) {
        [self removeAllTrackingAreas];
    }
    [super viewWillMoveToWindow:win];
}

// TODO: Not sure if this is used.
- (BOOL)shouldDrawInsertionPoint
{
    return NO;
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)isOpaque
{
    return YES;
}

- (void)setHighlightCursorLine:(BOOL)highlightCursorLine {
    _drawingHelper.highlightCursorLine = highlightCursorLine;
}

- (BOOL)highlightCursorLine {
    return _drawingHelper.highlightCursorLine;
}

- (void)setUseNonAsciiFont:(BOOL)useNonAsciiFont {
    _drawingHelper.useNonAsciiFont = useNonAsciiFont;
    _useNonAsciiFont = useNonAsciiFont;
    [self setNeedsDisplay:YES];
    [self updateMarkedTextAttributes];
}

- (void)setAntiAlias:(BOOL)asciiAntiAlias nonAscii:(BOOL)nonAsciiAntiAlias {
    _drawingHelper.asciiAntiAlias = asciiAntiAlias;
    _drawingHelper.nonAsciiAntiAlias = nonAsciiAntiAlias;
    [self setNeedsDisplay:YES];
}

- (void)setUseBoldFont:(BOOL)boldFlag {
    _useBoldFont = boldFlag;
    [self setNeedsDisplay:YES];
}

- (void)setThinStrokes:(iTermThinStrokesSetting)thinStrokes {
    _thinStrokes = thinStrokes;
    [self setNeedsDisplay:YES];
}

- (void)setAsciiLigatures:(BOOL)asciiLigatures {
    _asciiLigatures = asciiLigatures;
    [self setNeedsDisplay:YES];
}

- (void)setNonAsciiLigatures:(BOOL)nonAsciiLigatures {
    _nonAsciiLigatures = nonAsciiLigatures;
    [self setNeedsDisplay:YES];
}

- (void)setUseItalicFont:(BOOL)italicFlag
{
    _useItalicFont = italicFlag;
    [self setNeedsDisplay:YES];
}


- (void)setUseBoldColor:(BOOL)flag {
    _useBoldColor = flag;
    _drawingHelper.useBoldColor = flag;
    [self setNeedsDisplay:YES];
}

- (void)setBlinkAllowed:(BOOL)value {
    _drawingHelper.blinkAllowed = value;
    _blinkAllowed = value;
    [self setNeedsDisplay:YES];
}

- (void)setCursorNeedsDisplay {
    [self setNeedsDisplayInRect:[self rectWithHalo:[self cursorFrame]]];
}

- (void)setCursorType:(ITermCursorType)value {
    _drawingHelper.cursorType = value;
    [self markCursorDirty];
}

- (NSDictionary*)markedTextAttributes {
    return _markedTextAttributes;
}

- (void)setMarkedTextAttributes:(NSDictionary *)attr
{
    [_markedTextAttributes autorelease];
    _markedTextAttributes = [attr retain];
}

- (void)updateScrollerForBackgroundColor
{
    PTYScroller *scroller = [_delegate textViewVerticalScroller];
    NSColor *backgroundColor = [_colorMap colorForKey:kColorMapBackground];
    scroller.knobStyle =
        [backgroundColor isDark] ? NSScrollerKnobStyleLight : NSScrollerKnobStyleDefault;
}

- (NSFont *)font {
    return _primaryFont.font;
}

- (NSFont *)nonAsciiFont {
    return _useNonAsciiFont ? _secondaryFont.font : _primaryFont.font;
}

- (NSFont *)nonAsciiFontEvenIfNotUsed {
    return _secondaryFont.font;
}

+ (NSSize)charSizeForFont:(NSFont *)aFont
        horizontalSpacing:(double)hspace
          verticalSpacing:(double)vspace {
    FontSizeEstimator* fse = [FontSizeEstimator fontSizeEstimatorForFont:aFont];
    NSSize size = [fse size];
    size.width = ceil(size.width * hspace);
    size.height = ceil(vspace * ceil(size.height + [aFont leading]));
    return size;
}

- (void)setFont:(NSFont*)aFont
    nonAsciiFont:(NSFont *)nonAsciiFont
    horizontalSpacing:(double)horizontalSpacing
    verticalSpacing:(double)verticalSpacing
{
    NSSize sz = [PTYTextView charSizeForFont:aFont
                           horizontalSpacing:1.0
                             verticalSpacing:1.0];

    _charWidthWithoutSpacing = sz.width;
    _charHeightWithoutSpacing = sz.height;
    _horizontalSpacing = horizontalSpacing;
    _verticalSpacing = verticalSpacing;
    self.charWidth = ceil(_charWidthWithoutSpacing * horizontalSpacing);
    self.lineHeight = ceil(_charHeightWithoutSpacing * verticalSpacing);

    _primaryFont.font = aFont;
    _primaryFont.boldVersion = [_primaryFont computedBoldVersion];
    _primaryFont.italicVersion = [_primaryFont computedItalicVersion];
    _primaryFont.boldItalicVersion = [_primaryFont computedBoldItalicVersion];

    _secondaryFont.font = nonAsciiFont;
    _secondaryFont.boldVersion = [_secondaryFont computedBoldVersion];
    _secondaryFont.italicVersion = [_secondaryFont computedItalicVersion];
    _secondaryFont.boldItalicVersion = [_secondaryFont computedBoldItalicVersion];

    [self updateMarkedTextAttributes];

    NSScrollView* scrollview = [self enclosingScrollView];
    [scrollview setLineScroll:[self lineHeight]];
    [scrollview setPageScroll:2 * [self lineHeight]];
    [self updateNoteViewFrames];
    [_delegate textViewFontDidChange];

    // Refresh to avoid drawing before and after resize.
    [self refresh];
    [self setNeedsDisplay:YES];
}

- (void)changeFont:(id)fontManager
{
    if ([[[PreferencePanel sharedInstance] windowIfLoaded] isVisible]) {
        [[PreferencePanel sharedInstance] changeFont:fontManager];
    } else if ([[[PreferencePanel sessionsInstance] windowIfLoaded] isVisible]) {
        [[PreferencePanel sessionsInstance] changeFont:fontManager];
    }
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
    _drawingHelper.showTimestamps = !_drawingHelper.showTimestamps;
    [self setNeedsDisplay:YES];
}

- (BOOL)showTimestamps {
    return _drawingHelper.showTimestamps;
}

- (void)setShowTimestamps:(BOOL)value {
    _drawingHelper.showTimestamps = value;
    [self setNeedsDisplay:YES];
}

- (NSRect)scrollViewContentSize {
    NSRect r = NSMakeRect(0, 0, 0, 0);
    r.size = [[self enclosingScrollView] contentSize];
    return r;
}

// Number of extra lines below the last line of text that are always the background color.
// This is 2 except for just after the frame has changed and things are resizing.
- (double)excess {
    NSRect visible = [self scrollViewContentSize];
    visible.size.height -= [iTermAdvancedSettingsModel terminalVMargin] * 2;  // Height without top and bottom margins.
    int rows = visible.size.height / _lineHeight;
    double usablePixels = rows * _lineHeight;
    return MAX(visible.size.height - usablePixels + [iTermAdvancedSettingsModel terminalVMargin], [iTermAdvancedSettingsModel terminalVMargin]);  // Never have less than VMARGIN excess, but it can be more (if another tab has a bigger font)
}

- (CGFloat)desiredHeight {
    // Force the height to always be correct
    return ([_dataSource numberOfLines] * _lineHeight +
            [self excess] +
            _drawingHelper.numberOfIMELines * _lineHeight);
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self recomputeBadgeLabel];
}

// This exists to work around an apparent OS bug described in issue 2690. Under some circumstances
// (which I cannot reproduce) the key window will be an NSToolbarFullScreenWindow and the iTermTerminalWindow
// will be one of the main windows. NSToolbarFullScreenWindow doesn't appear to handle keystrokes,
// so they fall through to the main window. We'd like the cursor to blink and have other key-
// window behaviors in this case.
- (BOOL)isInKeyWindow
{
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

- (BOOL)isCursorBlinking {
    if (_blinkingCursor &&
        [self isInKeyWindow] &&
        [_delegate textViewIsActiveSession]) {
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)_isTextBlinking
{
    int width = [_dataSource width];
    int lineStart = ([self visibleRect].origin.y + [iTermAdvancedSettingsModel terminalVMargin]) / _lineHeight;  // add VMARGIN because stuff under top margin isn't visible.
    int lineEnd = ceil(([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / _lineHeight);
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [_dataSource numberOfLines]) {
        lineEnd = [_dataSource numberOfLines];
    }
    for (int y = lineStart; y < lineEnd; y++) {
        screen_char_t* theLine = [_dataSource getLineAtIndex:y];
        for (int x = 0; x < width; x++) {
            if (theLine[x].blink) {
                return YES;
            }
        }
    }

    return NO;
}

- (BOOL)_isAnythingBlinking {
    return [self isCursorBlinking] || (_blinkAllowed && [self _isTextBlinking]);
}

- (void)handleScrollbackOverflow:(int)scrollbackOverflow userScroll:(BOOL)userScroll {
    // Keep correct selection highlighted
    [_selection moveUpByLines:scrollbackOverflow];
    [_oldSelection moveUpByLines:scrollbackOverflow];

    // Keep the user's current scroll position.
    NSScrollView *scrollView = [self enclosingScrollView];
    BOOL canSkipRedraw = NO;
    if (userScroll) {
        NSRect scrollRect = [self visibleRect];
        double amount = [scrollView verticalLineScroll] * scrollbackOverflow;
        scrollRect.origin.y -= amount;
        if (scrollRect.origin.y < 0) {
            scrollRect.origin.y = 0;
        } else {
            // No need to redraw the whole screen because nothing is
            // changing because of the scroll.
            canSkipRedraw = YES;
        }
        [self scrollRectToVisible:scrollRect];
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
        [self setNeedsDisplay:YES];
    }

    // Move subviews up
    [self updateNoteViewFrames];

    NSAccessibilityPostNotification(self, NSAccessibilityRowCountChangedNotification);
}

// Update accessibility, to be called periodically.
- (void)refreshAccessibility {
    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
    long long absCursorY = ([_dataSource cursorY] + [_dataSource numberOfLines] +
                            [_dataSource totalScrollbackOverflow] - [_dataSource height]);
    if ([_dataSource cursorX] != _lastAccessibilityCursorX ||
        absCursorY != _lastAccessibiltyAbsoluteCursorY) {
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedTextChangedNotification);
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedRowsChangedNotification);
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedColumnsChangedNotification);
        _lastAccessibilityCursorX = [_dataSource cursorX];
        _lastAccessibiltyAbsoluteCursorY = absCursorY;
        if (UAZoomEnabled()) {
            CGRect viewRect = NSRectToCGRect(
                [self.window convertRectToScreen:[self convertRect:[self visibleRect] toView:nil]]);
            CGRect selectedRect = NSRectToCGRect(
                [self.window convertRectToScreen:[self convertRect:[self cursorFrame] toView:nil]]);
            viewRect.origin.y = ([[NSScreen mainScreen] frame].size.height -
                                 (viewRect.origin.y + viewRect.size.height));
            selectedRect.origin.y = ([[NSScreen mainScreen] frame].size.height -
                                     (selectedRect.origin.y + selectedRect.size.height));
            UAZoomChangeFocus(&viewRect, &selectedRect, kUAZoomFocusTypeInsertionPoint);
        }
    }
}

// This is called periodically. It updates the frame size, scrolls if needed, ensures selections
// and subviews are positioned correctly in case things scrolled
//
// Returns YES if blinking text or cursor was found.
- (BOOL)refresh {
    DLog(@"PTYTextView refresh called with delegate %@", _delegate);
    if (_dataSource == nil || _inRefresh) {
        return YES;
    }

    // Get the number of lines that have disappeared if scrollback buffer is full.
    int scrollbackOverflow = [_dataSource scrollbackOverflow];
    [_dataSource resetScrollbackOverflow];
    [_delegate textViewResizeFrameIfNeeded];
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
        [self scrollEnd];
    }

    // Update accessibility.
    [self refreshAccessibility];

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
    return [self updateDirtyRects] || [self isCursorBlinking];
}

- (void)setNeedsDisplayOnLine:(int)line
{
    [self setNeedsDisplayOnLine:line inRange:VT100GridRangeMake(0, _dataSource.width)];
}

// Overrides an NSView method.
- (NSRect)adjustScroll:(NSRect)proposedVisibleRect {
    proposedVisibleRect.origin.y = (int)(proposedVisibleRect.origin.y / _lineHeight + 0.5) * _lineHeight;
    return proposedVisibleRect;
}

- (void)scrollLineUp:(id)sender {
    [self scrollBy:-[self.enclosingScrollView verticalLineScroll]];
}

- (void)scrollLineDown:(id)sender {
    [self scrollBy:[self.enclosingScrollView verticalLineScroll]];
}

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

- (long long)absoluteScrollPosition
{
    NSRect visibleRect = [self visibleRect];
    long long localOffset = (visibleRect.origin.y + [iTermAdvancedSettingsModel terminalVMargin]) / [self lineHeight];
    return localOffset + [_dataSource totalScrollbackOverflow];
}

- (void)scrollToAbsoluteOffset:(long long)absOff height:(int)height
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = (absOff - [_dataSource totalScrollbackOverflow]) * _lineHeight - [iTermAdvancedSettingsModel terminalVMargin];
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = _lineHeight * height;
    [self scrollRectToVisible: aFrame];
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

- (void)scrollToSelection
{
    if ([_selection hasSelection]) {
        NSRect aFrame;
        VT100GridCoordRange range = [_selection spanningRange];
        aFrame.origin.x = 0;
        aFrame.origin.y = range.start.y * _lineHeight - [iTermAdvancedSettingsModel terminalVMargin];  // allow for top margin
        aFrame.size.width = [self frame].size.width;
        aFrame.size.height = (range.end.y - range.start.y + 1) * _lineHeight;
        [self scrollRectToVisible: aFrame];
        [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
    }
}

- (void)markCursorDirty {
    int currentCursorX = [_dataSource cursorX] - 1;
    int currentCursorY = [_dataSource cursorY] - 1;
    DLog(@"Mark cursor position %d, %d dirty.", currentCursorX, currentCursorY);
    [_dataSource setCharDirtyAtCursorX:currentCursorX Y:currentCursorY];
}

- (void)setCursorVisible:(BOOL)cursorVisible {
    [self markCursorDirty];
    _drawingHelper.cursorVisible = cursorVisible;
}

- (BOOL)cursorVisible {
    return _drawingHelper.cursorVisible;
}

- (CGFloat)minimumBaselineOffset {
    return _primaryFont.baselineOffset;
}

- (CGFloat)minimumUnderlineOffset {
    return _primaryFont.underlineOffset;
}

- (void)performBlockWithFlickerFixerGrid:(void (NS_NOESCAPE ^)(void))block {
    PTYTextViewSynchronousUpdateState *originalState = nil;
    PTYTextViewSynchronousUpdateState *savedState = [_dataSource setUseSavedGridIfAvailable:YES];
    if (savedState) {
        originalState = [[[PTYTextViewSynchronousUpdateState alloc] init] autorelease];
        originalState.colorMap = _colorMap;
        originalState.cursorVisible = _drawingHelper.cursorVisible;

        _drawingHelper.cursorVisible = savedState.cursorVisible;
        _drawingHelper.colorMap = savedState.colorMap;
        _colorMap = savedState.colorMap;
    }

    block();

    [_dataSource setUseSavedGridIfAvailable:NO];
    if (originalState) {
        _drawingHelper.colorMap = originalState.colorMap;
        _colorMap = originalState.colorMap;
        _drawingHelper.cursorVisible = originalState.cursorVisible;
    }
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
    _drawingHelper.reverseVideo = [[_dataSource terminal] reverseVideo];
    _drawingHelper.textViewIsActiveSession = [self.delegate textViewIsActiveSession];
    _drawingHelper.isInKeyWindow = [self isInKeyWindow];
    // Draw the cursor filled in when we're inactive if there's a popup open or key focus was stolen.
    _drawingHelper.shouldDrawFilledInCursor = ([self.delegate textViewShouldDrawFilledInCursor] || _keyFocusStolenCount);
    _drawingHelper.isFrontTextView = (self == [[iTermController sharedInstance] frontTextView]);
    _drawingHelper.transparencyAlpha = [self transparencyAlpha];
    _drawingHelper.now = [NSDate timeIntervalSinceReferenceDate];
    _drawingHelper.drawMarkIndicators = [_delegate textViewShouldShowMarkIndicators];
    _drawingHelper.thinStrokes = _thinStrokes;
    _drawingHelper.showSearchingCursor = _showSearchingCursor;
    _drawingHelper.baselineOffset = [self minimumBaselineOffset];
    _drawingHelper.underlineOffset = [self minimumUnderlineOffset];
    _drawingHelper.boldAllowed = _useBoldFont;
    _drawingHelper.unicodeVersion = [_delegate textViewUnicodeVersion];
    _drawingHelper.asciiLigatures = _primaryFont.hasDefaultLigatures || _asciiLigatures;
    _drawingHelper.nonAsciiLigatures = _secondaryFont.hasDefaultLigatures || _nonAsciiLigatures;
    _drawingHelper.copyMode = _delegate.textViewCopyMode;
    _drawingHelper.copyModeSelecting = _delegate.textViewCopyModeSelecting;
    _drawingHelper.copyModeCursorCoord = _delegate.textViewCopyModeCursorCoord;
    _drawingHelper.passwordInput = ([self isInKeyWindow] &&
                                    [_delegate textViewIsActiveSession] &&
                                    _delegate.textViewPasswordInput);

    CGFloat rightMargin = 0;
    if (_drawingHelper.showTimestamps) {
        [_drawingHelper createTimestampDrawingHelper];
        rightMargin = _drawingHelper.timestampDrawHelper.maximumWidth + 8;
    }
    _drawingHelper.indicatorFrame = [self configureIndicatorsHelperWithRightMargin:rightMargin];

    return _drawingHelper;
}

- (void)setAlphaValue:(CGFloat)alphaValue {
    DLog(@"Set textview alpha to %@", @(alphaValue));
    [super setAlphaValue:alphaValue];
}

- (void)setSuppressDrawing:(BOOL)suppressDrawing {
    if (suppressDrawing == _suppressDrawing) {
        return;
    }
    _suppressDrawing = suppressDrawing;
    PTYScrollView *scrollView = (PTYScrollView *)self.enclosingScrollView;
    [scrollView.verticalScroller setNeedsDisplay];
}

- (void)drawRect:(NSRect)rect {
    if (![_delegate textViewShouldDrawRect]) {
        // Metal code path in use
        [super drawRect:rect];
        return;
    }
    if (_dataSource.width <= 0) {
        ITCriticalError(_dataSource.width < 0, @"Negative datasource width of %@", @(_dataSource.width));
        return;
    }
    DLog(@"drawing document visible rect %@", NSStringFromRect(self.enclosingScrollView.documentVisibleRect));

    const NSRect *rectArray;
    NSInteger rectCount;
    [self getRectsBeingDrawn:&rectArray count:&rectCount];

    [self performBlockWithFlickerFixerGrid:^{
        // Initialize drawing helper
        [self drawingHelper];

        if (_drawingHook) {
            // This is used by tests to customize the draw helper.
            _drawingHook(_drawingHelper);
        }

        [_drawingHelper drawTextViewContentInRect:rect rectsPtr:rectArray rectCount:rectCount];

        [_indicatorsHelper drawInFrame:_drawingHelper.indicatorFrame];
        [_drawingHelper drawTimestamps];

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
}

- (BOOL)getAndResetDrawingAnimatedImageFlag {
    BOOL result = _drawingHelper.animated;
    _drawingHelper.animated = NO;
    return result;
}

- (NSRect)configureIndicatorsHelperWithRightMargin:(CGFloat)rightMargin {
    [_indicatorsHelper setIndicator:kiTermIndicatorMaximized
                            visible:[_delegate textViewIsMaximized]];
    [_indicatorsHelper setIndicator:kItermIndicatorBroadcastInput
                            visible:[_delegate textViewSessionIsBroadcastingInput]];
    [_indicatorsHelper setIndicator:kiTermIndicatorCoprocess
                            visible:[_delegate textViewHasCoprocess]];
    [_indicatorsHelper setIndicator:kiTermIndicatorAlert
                            visible:[_delegate alertOnNextMark]];
    [_indicatorsHelper setIndicator:kiTermIndicatorAllOutputSuppressed
                            visible:[_delegate textViewSuppressingAllOutput]];
    [_indicatorsHelper setIndicator:kiTermIndicatorZoomedIn
                            visible:[_delegate textViewIsZoomedIn]];
    [_indicatorsHelper setIndicator:kiTermIndicatorCopyMode
                            visible:[_delegate textViewCopyMode]];
    NSRect rect = self.visibleRect;
    rect.size.width -= rightMargin;
    return rect;
}

- (SmartMatch *)smartSelectAtX:(int)x
                             y:(int)y
                            to:(VT100GridWindowedRange *)rangePtr
              ignoringNewlines:(BOOL)ignoringNewlines
                actionRequired:(BOOL)actionRequred
               respectDividers:(BOOL)respectDividers {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    VT100GridCoord coord = VT100GridCoordMake(x, y);
    if (respectDividers) {
        [extractor restrictToLogicalWindowIncludingCoord:coord];
    }
    return [extractor smartSelectionAt:coord
                             withRules:_smartSelectionRules
                        actionRequired:actionRequred
                                 range:rangePtr
                      ignoringNewlines:ignoringNewlines];
}

- (BOOL)smartSelectAtX:(int)x y:(int)y ignoringNewlines:(BOOL)ignoringNewlines {
    VT100GridWindowedRange range;
    SmartMatch *smartMatch = [self smartSelectAtX:x
                                                y:y
                                               to:&range
                                 ignoringNewlines:ignoringNewlines
                                   actionRequired:NO
                                  respectDividers:[[iTermController sharedInstance] selectionRespectsSoftBoundaries]];

    [_selection beginSelectionAt:range.coordRange.start
                            mode:kiTermSelectionModeCharacter
                          resume:NO
                          append:NO];
    [_selection moveSelectionEndpointTo:range.coordRange.end];
    if (!ignoringNewlines) {
        // TODO(georgen): iTermSelection doesn't have a mode for smart selection ignoring newlines.
        // If that flag is set, it's better to leave the selection in character mode because you can
        // still extend a selection with shift-click. If we put it in smart mode, extending would
        // get confused.
        _selection.selectionMode = kiTermSelectionModeSmart;
    }
    [_selection endLiveSelection];
    return smartMatch != nil;
}

// Control-pgup and control-pgdown are handled at this level by NSWindow if no
// view handles it. It's necessary to setUserScroll in the PTYScroller, or else
// it scrolls back to the bottom right away. This code handles those two
// keypresses and scrolls correctly.
- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
    NSString* unmodkeystr = [theEvent charactersIgnoringModifiers];
    if ([unmodkeystr length] == 0) {
        return [super performKeyEquivalent:theEvent];
    }
    unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;

    NSUInteger modifiers = [theEvent modifierFlags];
    if ((modifiers & NSEventModifierFlagControl) &&
        (modifiers & NSEventModifierFlagFunction)) {
        switch (unmodunicode) {
            case NSPageUpFunctionKey:
                [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
                [self scrollPageUp:self];
                return YES;

            case NSPageDownFunctionKey:
                [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
                [self scrollPageDown:self];
                return YES;

            default:
                break;
        }
    }
    return [super performKeyEquivalent:theEvent];
}

// I haven't figured out how to test this code automatically, but a few things to try:
// * Repeats in US
// * Repeats in AquaSKK's Hiragana
// * Press L in AquaSKK's Hiragana to enter AquaSKK's ASCII
// * "special" keys, like Enter which go through doCommandBySelector
// * Repeated special keys
- (void)keyDown:(NSEvent *)event {
    [_altScreenMouseScrollInferer keyDown:event];
    if (![_delegate textViewShouldAcceptKeyDownEvent:event]) {
        return;
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

    DLog(@"PTYTextView keyDown BEGIN %@", event);
    id delegate = [self delegate];
    if ([delegate isPasting]) {
        [delegate queueKeyDown:event];
        return;
    }
    if ([_delegate textViewDelegateHandlesAllKeystrokes]) {
        DLog(@"PTYTextView keyDown: in instant replay, send to delegate");
        // Delegate has special handling for this case.
        [delegate keyDown:event];
        return;
    }
    unsigned int modflag = [event modifierFlags];
    unsigned short keyCode = [event keyCode];
    _hadMarkedTextBeforeHandlingKeypressEvent = [self hasMarkedText];
    BOOL rightAltPressed = (modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    BOOL leftAltPressed = (modflag & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;

    _keyIsARepeat = [event isARepeat];
    DLog(@"PTYTextView keyDown modflag=%d keycode=%d", modflag, (int)keyCode);
    DLog(@"_hadMarkedTextBeforeHandlingKeypressEvent=%d", (int)_hadMarkedTextBeforeHandlingKeypressEvent);
    DLog(@"hasActionableKeyMappingForEvent=%d", (int)[delegate hasActionableKeyMappingForEvent:event]);
    DLog(@"modFlag & (NSEventModifierFlagNumericPad | NSEventModifierFlagFunction)=%lu", (modflag & (NSEventModifierFlagNumericPad | NSEventModifierFlagFunction)));
    DLog(@"charactersIgnoringModififiers length=%d", (int)[[event charactersIgnoringModifiers] length]);
    DLog(@"delegate optionkey=%d, delegate rightOptionKey=%d", (int)[delegate optionKey], (int)[delegate rightOptionKey]);
    DLog(@"leftAltPressed && optionKey != NORMAL = %d", (int)(leftAltPressed && [delegate optionKey] != OPT_NORMAL));
    DLog(@"rightAltPressed && rightOptionKey != NORMAL = %d", (int)(rightAltPressed && [delegate rightOptionKey] != OPT_NORMAL));
    DLog(@"isControl=%d", (int)(modflag & NSEventModifierFlagControl));
    DLog(@"keycode is slash=%d, is backslash=%d", (keyCode == 0x2c), (keyCode == 0x2a));
    DLog(@"event is repeated=%d", _keyIsARepeat);

    // discard repeated key events if auto repeat mode (DECARM) is disabled
    if (_keyIsARepeat && ![[_dataSource terminal] autorepeatMode]) {
        return;
    }

    // Hide the cursor
    [NSCursor setHiddenUntilMouseMoves:YES];

    NSMutableArray *eventsToHandle = [NSMutableArray array];
    BOOL pointlessly;
    if ([_keyBindingEmulator handlesEvent:event pointlessly:&pointlessly extraEvents:eventsToHandle]) {
        if (!pointlessly) {
            DLog(@"iTermNSKeyBindingEmulator reports that event is handled, sending to interpretKeyEvents.");
            [self interpretKeyEvents:@[ event ]];
        } else {
            [self handleKeyDownEvent:event eschewCocoaTextHandling:YES];
        }
        return;
    }
    [eventsToHandle addObject:event];
    for (NSEvent *event in eventsToHandle) {
        [self handleKeyDownEvent:event eschewCocoaTextHandling:NO];
    }
}

- (void)handleKeyDownEvent:(NSEvent *)event eschewCocoaTextHandling:(BOOL)eschewCocoaTextHandling {
    id delegate = [self delegate];
    unsigned int modflag = [event modifierFlags];
    unsigned short keyCode = [event keyCode];
    BOOL rightAltPressed = (modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
    BOOL leftAltPressed = (modflag & NSEventModifierFlagOption) == NSEventModifierFlagOption && !rightAltPressed;

    // Should we process the event immediately in the delegate?
    if (!_hadMarkedTextBeforeHandlingKeypressEvent &&
        ([delegate hasActionableKeyMappingForEvent:event] ||       // delegate will do something useful
         (modflag & (NSEventModifierFlagNumericPad | NSEventModifierFlagFunction)) ||  // is an arrow key, f key, etc.
         ([[event charactersIgnoringModifiers] length] > 0 &&      // Will send Meta/Esc+ (length is 0 if it's a dedicated dead key)
          ((leftAltPressed && [delegate optionKey] != OPT_NORMAL) ||
           (rightAltPressed && [delegate rightOptionKey] != OPT_NORMAL))) ||
         ((modflag & NSEventModifierFlagControl) &&                          // a few special cases
          (keyCode == 0x2c /* slash */ || keyCode == 0x2a /* backslash */)))) {
             DLog(@"PTYTextView keyDown: process in delegate");
             [delegate keyDown:event];
             return;
    }

    DLog(@"Test for command key");

    if (modflag & NSEventModifierFlagCommand) {
        // You pressed cmd+something but it's not handled by the delegate. Going further would
        // send the unmodified key to the terminal which doesn't make sense.
        DLog(@"PTYTextView keyDown You pressed cmd+something");
        return;
    }

    // Control+Key doesn't work right with custom keyboard layouts. Handle ctrl+key here for the
    // standard combinations.
    BOOL workAroundControlBug = NO;
    if (!_hadMarkedTextBeforeHandlingKeypressEvent &&
        (modflag & (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption)) == NSEventModifierFlagControl) {
        DLog(@"Special ctrl+key handler running");

        NSString *unmodkeystr = [event charactersIgnoringModifiers];
        if ([unmodkeystr length] != 0) {
            unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
            unichar cc = 0xffff;
            if (unmodunicode >= 'a' && unmodunicode <= 'z') {
                cc = unmodunicode - 'a' + 1;
            } else if (unmodunicode == ' ' || unmodunicode == '2' || unmodunicode == '@') {
                cc = 0;
            } else if (unmodunicode == '[') {  // esc
                cc = 27;
            } else if (unmodunicode == '\\') {
                cc = 28;
            } else if (unmodunicode == ']') {
                cc = 29;
            } else if (unmodunicode == '^' || unmodunicode == '6') {
                cc = 30;
            } else if (unmodunicode == '-' || unmodunicode == '_') {
                cc = 31;
            }
            if (cc != 0xffff) {
                [self insertText:[NSString stringWithCharacters:&cc length:1]];
                DLog(@"PTYTextView keyDown work around control bug. cc=%d", (int)cc);
                workAroundControlBug = YES;
            }
        }
    }

    if (!workAroundControlBug) {
        // Let the IME process key events
        _keyPressHandled = NO;
        DLog(@"PTYTextView keyDown send to IME");

        // In issue 2743, it is revealed that in OS 10.9 this sometimes calls -insertText on the
        // wrong instnace of PTYTextView. We work around the issue by using a global variable to
        // track the instance of PTYTextView that is currently handling a key event and rerouting
        // calls as needed in -insertText and -doCommandBySelector.
        gCurrentKeyEventTextView = [[self retain] autorelease];

        if (!eschewCocoaTextHandling) {
            _eventBeingHandled = event;
            // TODO: Consider going straight to interpretKeyEvents: for repeats. See issue 6052.
            if ([iTermAdvancedSettingsModel experimentalKeyHandling]) {
              // This may cause -insertText:replacementRange: or -doCommandBySelector: to be called.
              // These methods have a side-effect of setting _keyPressHandled if they dispatched the event
              // to the delegate. They might not get called: for example, if you hold down certain keys
              // then repeats might be ignored, or the IME might handle it internally (such as when you press
              // "L" in AquaSKK's Hiragana mode to enter ASCII mode. See pull request 279 for more on this.
              [self.inputContext handleEvent:event];
            } else {
              [self interpretKeyEvents:[NSArray arrayWithObject:event]];
            }
            if (_eventBeingHandled == event) {
                _eventBeingHandled = nil;
            }
        }
        gCurrentKeyEventTextView = nil;

        // Handle repeats.
        BOOL shouldPassToDelegate = (!_hadMarkedTextBeforeHandlingKeypressEvent && !_keyPressHandled && ![self hasMarkedText]);
        if ([iTermAdvancedSettingsModel experimentalKeyHandling]) {
            shouldPassToDelegate &= event.isARepeat;
        }
        if (eschewCocoaTextHandling) {
            // It was never sent tp cocoa so the delegate must take it
            shouldPassToDelegate = YES;
        }
        if (shouldPassToDelegate) {
            DLog(@"PTYTextView keyDown unhandled (likely repeated) keypress with no IME, send to delegate");
            [delegate keyDown:event];
        }
    }
    DLog(@"PTYTextView keyDown END");
}

- (BOOL)keyIsARepeat {
    return (_keyIsARepeat);
}

// WARNING: This indicates if mouse reporting is a possiblity. -terminalWantsMouseReports indicates
// if the reporting mode would cause any action to be taken if this returns YES. They should be used
// in conjunction most of the time.
- (BOOL)xtermMouseReporting {
    NSEvent *event = [NSApp currentEvent];
    return (([[self delegate] xtermMouseReporting]) &&        // Xterm mouse reporting is on
            !([event modifierFlags] & NSEventModifierFlagOption));   // Not holding Opt to disable mouse reporting
}

- (BOOL)xtermMouseReportingAllowMouseWheel {
    return [[self delegate] xtermMouseReportingAllowMouseWheel];
}

// If mouse reports are sent to the delegate, will it use them? Use with -xtermMouseReporting, which
// understands Option to turn off reporting.
- (BOOL)terminalWantsMouseReports {
    MouseMode mouseMode = [[_dataSource terminal] mouseMode];
    return ([_delegate xtermMouseReporting] &&
            mouseMode != MOUSE_REPORTING_NONE &&
            mouseMode != MOUSE_REPORTING_HILITE);
}

// TODO: disable other, right mouse for inactive panes
- (void)otherMouseDown:(NSEvent *)event {
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    [self reportMouseEvent:event];

    [pointer_ mouseDown:event
            withTouches:_numTouches
           ignoreOption:[self terminalWantsMouseReports]];
}

- (void)otherMouseUp:(NSEvent *)event
{
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    if ([self reportMouseEvent:event]) {
        return;
    }

    if (!_mouseDownIsThreeFingerClick) {
        DLog(@"Sending third button press up to super");
        [super otherMouseUp:event];
    }
    DLog(@"Sending third button press up to pointer controller");
    [pointer_ mouseUp:event withTouches:_numTouches];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    if ([self reportMouseEvent:event]) {
        return;
    }
    [super otherMouseDragged:event];
}

- (void)rightMouseDown:(NSEvent*)event {
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    if ([threeFingerTapGestureRecognizer_ rightMouseDown:event]) {
        DLog(@"Cancel right mouse down");
        return;
    }
    if ([pointer_ mouseDown:event
                withTouches:_numTouches
               ignoreOption:[self terminalWantsMouseReports]]) {
        return;
    }
    if ([self reportMouseEvent:event]) {
        return;
    }

    [super rightMouseDown:event];
}

- (void)rightMouseUp:(NSEvent *)event {
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    if ([threeFingerTapGestureRecognizer_ rightMouseUp:event]) {
        return;
    }

    if ([pointer_ mouseUp:event withTouches:_numTouches]) {
        return;
    }
    if ([self reportMouseEvent:event]) {
        return;
    }
    [super rightMouseUp:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    if ([self reportMouseEvent:event]) {
        return;
    }
    [super rightMouseDragged:event];
}

- (BOOL)scrollWheelShouldSendDataForEvent:(NSEvent *)event at:(NSPoint)point {
    NSRect liveRect = [self liveRect];
    if (!NSPointInRect(point, liveRect)) {
        return NO;
    }
    if (event.type != NSEventTypeScrollWheel) {
        return NO;
    }
    if (![self.dataSource showingAlternateScreen]) {
        return NO;
    }
    if ([self shouldReportMouseEvent:event at:point] &&
        [[_dataSource terminal] mouseMode] != MOUSE_REPORTING_NONE) {
        // Prefer to report the scroll than to send arrow keys in this mouse reporting mode.
        return NO;
    }
    if (event.modifierFlags & NSEventModifierFlagOption) {
        // Hold alt to disable sending arrow keys.
        return NO;
    }
    BOOL alternateMouseScroll = [iTermAdvancedSettingsModel alternateMouseScroll];
    NSString *upString = [iTermAdvancedSettingsModel alternateMouseScrollStringForUp];
    NSString *downString = [iTermAdvancedSettingsModel alternateMouseScrollStringForDown];

    if (alternateMouseScroll || upString.length || downString.length) {
        return YES;
    } else {
        [_altScreenMouseScrollInferer scrollWheel:event];
        return NO;
    }
}

- (NSString *)stringToSendForScrollEvent:(NSEvent *)event deltaY:(CGFloat)deltaY forceLatin1:(BOOL *)forceLatin1 {
    const BOOL down = (deltaY < 0);

    if ([iTermAdvancedSettingsModel alternateMouseScroll]) {
        *forceLatin1 = YES;
        NSData *data = down ? [_dataSource.terminal.output keyArrowDown:event.modifierFlags] :
                              [_dataSource.terminal.output keyArrowUp:event.modifierFlags];
        return [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    } else {
        *forceLatin1 = NO;
        NSString *string = down ? [iTermAdvancedSettingsModel alternateMouseScrollStringForDown] :
                                  [iTermAdvancedSettingsModel alternateMouseScrollStringForUp];
        return [string stringByExpandingVimSpecialCharacters];
    }
}

- (void)jiggle {
    [self scrollLineUp:nil];
    [self scrollLineDown:nil];
}

- (void)scrollWheel:(NSEvent *)event {
    DLog(@"scrollWheel:%@", event);

    if (!_haveSeenScrollWheelEvent) {
        // Work around a weird bug. Commit 9e4b97b18fac24bea6147c296b65687f0523ad83 caused it.
        // When you restore a window and have an inline scroller (but not a legacy scroller!) then
        // it will be at the top, even though we're scrolled to the bottom. You can either jiggle
        // it after a delay to fix it, or after thousands of dispatch_async calls, or here. None of
        // these make any sense, nor does the bug itself. I get the feeling that a giant rats' nest
        // of insanity underlies scroll wheels on macOS.
        _haveSeenScrollWheelEvent = YES;
        [self jiggle];
    }
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    if ([self scrollWheelShouldSendDataForEvent:event at:point]) {
        DLog(@"Scroll wheel sending data");

        PTYScrollView *scrollView = (PTYScrollView *)self.enclosingScrollView;
        CGFloat deltaY = [scrollView accumulateVerticalScrollFromEvent:event];
        BOOL forceLatin1 = NO;
        NSString *stringToSend = [self stringToSendForScrollEvent:event deltaY:deltaY forceLatin1:&forceLatin1];
        if (stringToSend) {
            for (int i = 0; i < ceil(fabs(deltaY)); i++) {
                if (forceLatin1) {
                    [_delegate writeStringWithLatin1Encoding:stringToSend];
                } else {
                    [_delegate writeTask:stringToSend];
                }
            }
        }
    } else if (![self reportMouseEvent:event]) {
        [super scrollWheel:event];
    }
}

- (BOOL)setCursor:(NSCursor *)cursor {
    if (cursor == cursor_) {
        return NO;
    }
    [cursor_ autorelease];
    cursor_ = [cursor retain];
    return YES;
}

- (BOOL)mouseIsOverImageInEvent:(NSEvent *)event {
    NSPoint point = [self clickPoint:event allowRightMarginOverflow:NO];
    return [self imageInfoAtCoord:VT100GridCoordMake(point.x, point.y)] != nil;
}

- (void)updateCursor:(NSEvent *)event {
    [self updateCursor:event action:nil];
}

- (void)updateCursor:(NSEvent *)event action:(URLAction *)action {
    NSString *hover = nil;
    BOOL changed = NO;
    if (([event modifierFlags] & kDragPaneModifiers) == kDragPaneModifiers) {
        changed = [self setCursor:[NSCursor openHandCursor]];
    } else if (([event modifierFlags] & kRectangularSelectionModifierMask) == kRectangularSelectionModifiers) {
        changed = [self setCursor:[NSCursor crosshairCursor]];
    } else if (action &&
               ([event modifierFlags] & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) == NSEventModifierFlagCommand) {
        changed = [self setCursor:[NSCursor pointingHandCursor]];
        if (action.hover && action.string.length) {
            hover = action.string;
        }
    } else if ([self mouseIsOverImageInEvent:event]) {
        changed = [self setCursor:[NSCursor arrowCursor]];
    } else if ([self xtermMouseReporting] &&
               [self terminalWantsMouseReports]) {
        changed = [self setCursor:[iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeamWithCircle]];
    } else {
        changed = [self setCursor:[iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeam]];
    }
    if (changed) {
        [self.enclosingScrollView setDocumentCursor:cursor_];
    }
    [_delegate textViewShowHoverURL:hover];
}

- (BOOL)hasUnderline {
    return _drawingHelper.underlinedRange.coordRange.start.x >= 0;
}

// Reset underlined chars indicating cmd-clicakble url.
- (void)removeUnderline {
    if (![self hasUnderline]) {
        return;
    }
    _drawingHelper.underlinedRange =
        VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), 0, 0);
    [self setNeedsDisplay:YES];  // It would be better to just display the underlined/formerly underlined area.
}

// Update range of underlined chars indicating cmd-clicakble url.
- (URLAction *)updateUnderlinedURLs:(NSEvent *)event {
    URLAction *action = nil;
    if (([event modifierFlags] & NSEventModifierFlagCommand) && (self.window.isKeyWindow ||
                                                       [iTermAdvancedSettingsModel cmdClickWhenInactiveInvokesSemanticHistory])) {
        NSPoint screenPoint = [NSEvent mouseLocation];
        NSRect windowRect = [[self window] convertRectFromScreen:NSMakeRect(screenPoint.x,
                                                                            screenPoint.y,
                                                                            0,
                                                                            0)];
        NSPoint locationInTextView = [self convertPoint:windowRect.origin fromView: nil];
        if (!NSPointInRect(locationInTextView, [self bounds])) {
            [self removeUnderline];
            return action;
        }
        NSPoint viewPoint = [self windowLocationToRowCol:windowRect.origin allowRightMarginOverflow:NO];
        int x = viewPoint.x;
        int y = viewPoint.y;
        if (![iTermPreferences boolForKey:kPreferenceKeyCmdClickOpensURLs] || y < 0) {
            [self removeUnderline];
            return action;
        } else {
            action = [self urlActionForClickAtX:x
                                              y:y
                         respectingHardNewlines:![self ignoreHardNewlinesInURLs]];
            if (action) {
                if ([iTermAdvancedSettingsModel enableUnderlineSemanticHistoryOnCmdHover]) {
                    _drawingHelper.underlinedRange = VT100GridAbsWindowedRangeFromRelative(action.range, [_dataSource totalScrollbackOverflow]);
                }

                if (action.actionType == kURLActionOpenURL) {
                    NSURL *url = [NSURL URLWithUserSuppliedString:action.string];
                    if (url && url.host) {
                        [self setNeedsDisplay:YES];
                    }
                }
            } else {
                [self removeUnderline];
                return action;
            }
        }
    } else {
        [self removeUnderline];
        return action;
    }

    [self setNeedsDisplay:YES];  // It would be better to just display the underlined/formerly underlined area.
    return action;
}

- (void)flagsChanged:(NSEvent *)theEvent {
    URLAction *action = [self updateUnderlinedURLs:theEvent];
    [self updateCursor:theEvent action:action];
    [super flagsChanged:theEvent];
}

- (void)swipeWithEvent:(NSEvent *)event
{
    [pointer_ swipeWithEvent:event];
}

// Uses an undocumented/deprecated API to receive key presses even when inactive.
- (BOOL)stealKeyFocus {
    // Make sure everything needed for focus stealing exists in this version of Mac OS.
    CPSGetCurrentProcessFunction *getCurrentProcess = GetCPSGetCurrentProcessFunction();
    CPSStealKeyFocusFunction *stealKeyFocus = GetCPSStealKeyFocusFunction();
    CPSReleaseKeyFocusFunction *releaseKeyFocus = GetCPSReleaseKeyFocusFunction();

    if (!getCurrentProcess || !stealKeyFocus || !releaseKeyFocus) {
        return NO;
    }

    CPSProcessSerNum psn;
    if (getCurrentProcess(&psn) == noErr) {
        OSErr err = stealKeyFocus(&psn);
        DLog(@"CPSStealKeyFocus returned %d", (int)err);
        // CPSStealKeyFocus appears to succeed even when it returns an error. See issue 4113.
        return YES;
    }

    return NO;
}

// Undoes -stealKeyFocus.
- (void)releaseKeyFocus {
    CPSGetCurrentProcessFunction *getCurrentProcess = GetCPSGetCurrentProcessFunction();
    CPSReleaseKeyFocusFunction *releaseKeyFocus = GetCPSReleaseKeyFocusFunction();

    if (!getCurrentProcess || !releaseKeyFocus) {
        return;
    }

    CPSProcessSerNum psn;
    if (getCurrentProcess(&psn) == noErr) {
        DLog(@"CPSReleaseKeyFocus");
        releaseKeyFocus(&psn);
    }
}


- (void)mouseExited:(NSEvent *)event {
    DLog(@"Mouse exited %@", self);
    if (_keyFocusStolenCount) {
        DLog(@"Releasing key focus %d times", (int)_keyFocusStolenCount);
        for (int i = 0; i < _keyFocusStolenCount; i++) {
            [self releaseKeyFocus];
        }
        _keyFocusStolenCount = 0;
        [self setNeedsDisplay:YES];
    }
    if ([NSApp isActive]) {
        [self resetMouseLocationToRefuseFirstResponderAt];
    } else {
        DLog(@"Ignore mouse exited because app is not active");
    }
    [self updateUnderlinedURLs:event];
    [_delegate textViewShowHoverURL:nil];
}

- (void)mouseEntered:(NSEvent *)event {
    DLog(@"Mouse entered %@", self);
    if ([iTermAdvancedSettingsModel stealKeyFocus] &&
        [iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse]) {
        DLog(@"Trying to steal key focus");
        if ([self stealKeyFocus]) {
            ++_keyFocusStolenCount;
            [self setNeedsDisplay:YES];
        }
    }
    [self updateCursor:event action:[self updateUnderlinedURLs:event]];
    if ([iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse] &&
        [[self window] alphaValue] > 0 &&
        ![NSApp modalWindow]) {
        // Some windows automatically close when they lose key status and are
        // incompatible with FFM. Check if the key window or its controller implements
        // disableFocusFollowsMouse and if it returns YES do nothing.
        id obj = nil;
        if ([[NSApp keyWindow] respondsToSelector:@selector(disableFocusFollowsMouse)]) {
            obj = [NSApp keyWindow];
        } else if ([[[NSApp keyWindow] windowController] respondsToSelector:@selector(disableFocusFollowsMouse)]) {
            obj = [[NSApp keyWindow] windowController];
        }
        if (!NSEqualPoints(_mouseLocationToRefuseFirstResponderAt, [NSEvent mouseLocation])) {
            DLog(@"%p Mouse location is %@, refusal point is %@", self, NSStringFromPoint([NSEvent mouseLocation]), NSStringFromPoint(_mouseLocationToRefuseFirstResponderAt));
            if ([iTermAdvancedSettingsModel stealKeyFocus]) {
                if (![obj disableFocusFollowsMouse]) {
                    [[self window] makeKeyWindow];
                }
            } else {
                if ([NSApp isActive] && ![obj disableFocusFollowsMouse]) {
                    [[self window] makeKeyWindow];
                }
            }
            if ([self isInKeyWindow]) {
                [_delegate textViewDidBecomeFirstResponder];
            }
        } else {
            DLog(@"%p Refusing first responder on enter", self);
        }
    }
}

- (NSPoint)pointForCoord:(VT100GridCoord)coord {
    return NSMakePoint([iTermAdvancedSettingsModel terminalMargin] + coord.x * _charWidth,
                       coord.y * _lineHeight);
}

- (VT100GridCoord)coordForPointInWindow:(NSPoint)point {
    // TODO: Merge this function with windowLocationToRowCol.
    NSPoint p = [self windowLocationToRowCol:point allowRightMarginOverflow:NO];
    return VT100GridCoordMake(p.x, p.y);
}

// TODO: this should return a VT100GridCoord but it confusingly returns an NSPoint.
//
// If allowRightMarginOverflow is YES then the returned value's x coordinate may be equal to
// dataSource.width. If NO, then it will always be less than dataSource.width.
- (NSPoint)windowLocationToRowCol:(NSPoint)locationInWindow
         allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    NSPoint locationInTextView = [self convertPoint:locationInWindow fromView: nil];

    VT100GridCoord coord = [self coordForPoint:locationInTextView allowRightMarginOverflow:allowRightMarginOverflow];
    return NSMakePoint(coord.x, coord.y);
}

- (VT100GridCoord)coordForPoint:(NSPoint)locationInTextView allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    int x, y;
    int width = [_dataSource width];

    x = (locationInTextView.x - [iTermAdvancedSettingsModel terminalMargin] + _charWidth * [iTermAdvancedSettingsModel fractionOfCharacterSelectingNextNeighbor]) / _charWidth;
    if (x < 0) {
        x = 0;
    }
    y = locationInTextView.y / _lineHeight;

    int limit;
    if (allowRightMarginOverflow) {
        limit = width;
    } else {
        limit = width - 1;
    }
    x = MIN(x, limit);
    y = MIN(y, [_dataSource numberOfLines] - 1);

    return VT100GridCoordMake(x, y);
}

- (NSPoint)clickPoint:(NSEvent *)event allowRightMarginOverflow:(BOOL)allowRightMarginOverflow {
    NSPoint locationInWindow = [event locationInWindow];
    return [self windowLocationToRowCol:locationInWindow
               allowRightMarginOverflow:allowRightMarginOverflow];
}

- (void)mouseDown:(NSEvent *)event {
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    if ([threeFingerTapGestureRecognizer_ mouseDown:event]) {
        return;
    }
    DLog(@"Mouse Down on %@ with event %@, num touches=%d", self, event, _numTouches);
    if ([self mouseDownImpl:event]) {
        [super mouseDown:event];
    }
}

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
        [self otherMouseUp:fakeEvent];
    }
    _numTouches = saved;
    if (!isDown) {
        _mouseDownIsThreeFingerClick = isDown;
        DLog(@"emulateThirdButtonPressDown - set mouseDownIsThreeFingerClick=NO");
    }
}

- (void)pressureChangeWithEvent:(NSEvent *)event {
    [pointer_ pressureChangeWithEvent:event];
}

// Returns yes if [super mouseDown:event] should be run by caller.
- (BOOL)mouseDownImpl:(NSEvent*)event {
    DLog(@"mouseDownImpl: called");
    _mouseDownWasFirstMouse = ([event eventNumber] == _firstMouseEventNumber) || ![NSApp keyWindow];
    const BOOL altPressed = ([event modifierFlags] & NSEventModifierFlagOption) != 0;
    BOOL cmdPressed = ([event modifierFlags] & NSEventModifierFlagCommand) != 0;
    const BOOL shiftPressed = ([event modifierFlags] & NSEventModifierFlagShift) != 0;
    const BOOL ctrlPressed = ([event modifierFlags] & NSEventModifierFlagControl) != 0;
    if (gDebugLogging && altPressed && cmdPressed && shiftPressed && ctrlPressed) {
        // Dump view hierarchy
        NSBeep();
        [[iTermController sharedInstance] dumpViewHierarchy];
        return NO;
    }
    PTYTextView* frontTextView = [[iTermController sharedInstance] frontTextView];
    if (frontTextView != self &&
        !cmdPressed &&
        [iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse]) {
        // Clicking in an inactive pane with focus follows mouse makes it active.
        // Becuase of how FFM works, this would only happen if another app were key.
        // See issue 3163.
        DLog(@"Click on inactive pane with focus follows mouse");
        _mouseDownWasFirstMouse = YES;
        [[self window] makeFirstResponder:self];
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
        return NO;
    }
    [pointer_ notifyLeftMouseDown];
    _mouseDownIsThreeFingerClick = NO;
    DLog(@"mouseDownImpl - set mouseDownIsThreeFingerClick=NO");
    if (([event modifierFlags] & kDragPaneModifiers) == kDragPaneModifiers) {
        [_delegate textViewBeginDrag];
        DLog(@"Returning because of drag starting");
        return NO;
    }
    if (_numTouches == 3) {
        if ([iTermPreferences boolForKey:kPreferenceKeyThreeFingerEmulatesMiddle]) {
            [self emulateThirdButtonPressDown:YES withEvent:event];
        } else {
            // Perform user-defined gesture action, if any
            [pointer_ mouseDown:event
                    withTouches:_numTouches
                   ignoreOption:[self terminalWantsMouseReports]];
            DLog(@"Set mouseDown=YES because of 3 finger mouseDown (not emulating middle)");
            _mouseDown = YES;
        }
        DLog(@"Returning because of 3-finger click.");
        return NO;
    }
    if ([pointer_ eventEmulatesRightClick:event]) {
        [pointer_ mouseDown:event
                withTouches:_numTouches
               ignoreOption:[self terminalWantsMouseReports]];
        DLog(@"Returning because emulating right click.");
        return NO;
    }

    dragOk_ = YES;
    if (cmdPressed) {
        if (frontTextView != self) {
            if ([NSApp keyWindow] != [self window]) {
                // A cmd-click in in inactive window makes the pane active.
                DLog(@"Cmd-click in inactive window");
                _mouseDownWasFirstMouse = YES;
                [[self window] makeFirstResponder:self];
                DLog(@"Returning because of cmd-click in inactive window.");
                return NO;
            }
        } else if ([NSApp keyWindow] != [self window]) {
            // A cmd-click in an active session in a non-key window acts like a click without cmd.
            // This can be changed in advanced settings so cmd-click will still invoke semantic
            // history even for non-key windows.
            DLog(@"Cmd-click in active session in non-key window");
            cmdPressed = [iTermAdvancedSettingsModel cmdClickWhenInactiveInvokesSemanticHistory];
        }
    }
    if (([event modifierFlags] & kDragPaneModifiers) == kDragPaneModifiers) {
        DLog(@"Returning because of drag modifiers.");
        return YES;
    }

    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
    int x = clickPoint.x;
    int y = clickPoint.y;

    if (_numTouches <= 1) {
        for (NSView *view in [self subviews]) {
            if ([view isKindOfClass:[PTYNoteView class]]) {
                PTYNoteView *noteView = (PTYNoteView *)view;
                [noteView.delegate.noteViewController setNoteHidden:YES];
            }
        }
    }

    DLog(@"Set mouseDown=YES.");
    _mouseDown = YES;

    if ([self reportMouseEvent:event]) {
        DLog(@"Returning because mouse event reported.");
        [_selection clearSelection];
        return NO;
    }

    if (!_mouseDownWasFirstMouse) {
        // Lock auto scrolling while the user is selecting text, but not for a first-mouse event
        // because drags are ignored for those.
        [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
    }

    [_mouseDownEvent autorelease];
    _mouseDownEvent = [event retain];
    _mouseDragged = NO;
    _mouseDownOnSelection = NO;
    _mouseDownOnImage = NO;

    int clickCount = [event clickCount];
    DLog(@"clickCount=%d altPressed=%d cmdPressed=%d", clickCount, (int)altPressed, (int)cmdPressed);
    const BOOL isExtension = ([_selection hasSelection] && shiftPressed);
    if (isExtension && [_selection hasSelection]) {
        if (!_selection.live) {
            [_selection beginExtendingSelectionAt:VT100GridCoordMake(x, y)];
        }
    } else if (clickCount < 2) {
        // single click
        iTermSelectionMode mode;
        if ((event.modifierFlags & kRectangularSelectionModifierMask) == kRectangularSelectionModifiers) {
            mode = kiTermSelectionModeBox;
        } else {
            mode = kiTermSelectionModeCharacter;
        }

        if ((_imageBeingClickedOn = [self imageInfoAtCoord:VT100GridCoordMake(x, y)])) {
            _mouseDownOnImage = YES;
            _selection.appending = NO;
        } else if ([_selection containsCoord:VT100GridCoordMake(x, y)]) {
            // not holding down shift key but there is an existing selection.
            // Possibly a drag coming up (if a cmd-drag follows)
            DLog(@"mouse down on selection, returning");
            _mouseDownOnSelection = YES;
            _selection.appending = NO;
            return YES;
        } else {
            // start a new selection
            [_selection beginSelectionAt:VT100GridCoordMake(x, y)
                                    mode:mode
                                  resume:NO
                                  append:(cmdPressed && !altPressed)];
            _selection.resumable = YES;
        }
    } else if ([self shouldSelectWordWithClicks:clickCount]) {
        [_selection beginSelectionAt:VT100GridCoordMake(x, y)
                                mode:kiTermSelectionModeWord
                              resume:YES
                              append:_selection.appending];
    } else if (clickCount == 3) {
        BOOL wholeLines =
            [iTermPreferences boolForKey:kPreferenceKeyTripleClickSelectsFullWrappedLines];
        iTermSelectionMode mode =
            wholeLines ? kiTermSelectionModeWholeLine : kiTermSelectionModeLine;

        [_selection beginSelectionAt:VT100GridCoordMake(x, y)
                                mode:mode
                              resume:YES
                              append:_selection.appending];
    } else if ([self shouldSmartSelectWithClicks:clickCount]) {
        [_selection beginSelectionAt:VT100GridCoordMake(x, y)
                                mode:kiTermSelectionModeSmart
                              resume:YES
                              append:_selection.appending];
    }

    DLog(@"Mouse down. selection set to %@", _selection);
    [_delegate refresh];

    DLog(@"Reached end of mouseDownImpl.");
    return NO;
}

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

static double Square(double n) {
    return n * n;
}

static double EuclideanDistance(NSPoint p1, NSPoint p2) {
    return sqrt(Square(p1.x - p2.x) + Square(p1.y - p2.y));
}

- (void)mouseUp:(NSEvent *)event {
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    if ([threeFingerTapGestureRecognizer_ mouseUp:event]) {
        return;
    }
    DLog(@"Mouse Up on %@ with event %@, numTouches=%d", self, event, _numTouches);
    _firstMouseEventNumber = -1;  // Synergy seems to interfere with event numbers, so reset it here.
    if (_mouseDownIsThreeFingerClick) {
        [self emulateThirdButtonPressDown:NO withEvent:event];
        DLog(@"Returning from mouseUp because mouse-down was a 3-finger click");
        return;
    } else if (_numTouches == 3 && mouseDown) {
        // Three finger tap is valid but not emulating middle button
        [pointer_ mouseUp:event withTouches:_numTouches];
        _mouseDown = NO;
        DLog(@"Returning from mouseUp because there were 3 touches. Set mouseDown=NO");
        return;
    }
    dragOk_ = NO;
    _semanticHistoryDragged = NO;
    if ([pointer_ eventEmulatesRightClick:event]) {
        [pointer_ mouseUp:event withTouches:_numTouches];
        DLog(@"Returning from mouseUp because we'e emulating a right click.");
        return;
    }
    const BOOL cmdActuallyPressed = (([event modifierFlags] & NSEventModifierFlagCommand) != 0);
    // Make an exception to the first-mouse rule when cmd-click is set to always invoke
    // semantic history.
    const BOOL cmdPressed = cmdActuallyPressed && (!_mouseDownWasFirstMouse ||
                                                   [iTermAdvancedSettingsModel cmdClickWhenInactiveInvokesSemanticHistory]);
    if (mouseDown == NO) {
        DLog(@"Returning from mouseUp because the mouse was never down.");
        return;
    }
    DLog(@"Set mouseDown=NO");
    _mouseDown = NO;

    [_selectionScrollHelper mouseUp];

    BOOL isUnshiftedSingleClick = ([event clickCount] < 2 &&
                                   !_mouseDragged &&
                                   !([event modifierFlags] & NSEventModifierFlagShift));
    BOOL isShiftedSingleClick = ([event clickCount] == 1 &&
                                 !_mouseDragged &&
                                 ([event modifierFlags] & NSEventModifierFlagShift));
    BOOL willFollowLink = (isUnshiftedSingleClick &&
                           cmdPressed &&
                           [iTermPreferences boolForKey:kPreferenceKeyCmdClickOpensURLs]);

    // Reset _mouseDragged; it won't be needed again and we don't want it to get stuck like in
    // issue 3766.
    _mouseDragged = NO;

    // Send mouse up event to host if xterm mouse reporting is on
    if ([self reportMouseEvent:event]) {
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
            [self openTargetWithEvent:event];
        }
        DLog(@"Returning from mouseUp because the mouse event was reported.");
        return;
    }

    // Unlock auto scrolling as the user as finished selecting text
    if (([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / _lineHeight ==
        [_dataSource numberOfLines]) {
        [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:NO];
    }

    if (!cmdActuallyPressed) {
        // Make ourselves the first responder except on cmd-click. A cmd-click on a non-key window
        // gets treated as a click that doesn't raise the window. A cmd-click in an inactive pane
        // in the key window shouldn't make it first responder, but still gets treated as cmd-click.
        //
        // We use cmdActuallyPressed instead of cmdPressed because on first-mouse cmdPressed gets
        // unset so this function generally behaves like it got a plain click (this is the exception).
        [[self window] makeFirstResponder:self];
    }

    [_selection endLiveSelection];
    if (isUnshiftedSingleClick) {
        // Just a click in the window.
        DLog(@"is a click in the window");

        BOOL altPressed = ([event modifierFlags] & NSEventModifierFlagOption) != 0;
        if (altPressed &&
            [iTermPreferences boolForKey:kPreferenceKeyOptionClickMovesCursor] &&
            !_mouseDownWasFirstMouse) {
            // This moves the cursor, but not if mouse reporting is on for button clicks.
            // It's also off for first mouse because of issue 2943 (alt-click to activate an app
            // is used to order-back all of the previously active app's windows).
            VT100Terminal *terminal = [_dataSource terminal];
            switch ([terminal mouseMode]) {
                case MOUSE_REPORTING_NORMAL:
                case MOUSE_REPORTING_BUTTON_MOTION:
                case MOUSE_REPORTING_ALL_MOTION:
                    // Reporting mouse clicks. The remote app gets preference.
                    break;

                default: {
                    // Not reporting mouse clicks, so we'll move the cursor since the remote app
                    // can't.
                    VT100GridCoord coord = [self coordForPointInWindow:[event locationInWindow]];
                    BOOL verticalOk;
                    if (!cmdPressed &&
                        [_delegate textViewShouldPlaceCursorAt:coord verticalOk:&verticalOk]) {
                        [self placeCursorOnCurrentLineWithEvent:event verticalOk:verticalOk];
                    }
                    break;
                }
            }
        }

        if (!_selection.appending) {
            [_selection clearSelection];
        }
        if (willFollowLink) {
            if (altPressed) {
                [self openTargetInBackgroundWithEvent:event];
            } else {
                [self openTargetWithEvent:event];
            }
        } else {
            NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
            [_findOnPageHelper setStartPoint:VT100GridAbsCoordMake(clickPoint.x,
                                                                   [_dataSource totalScrollbackOverflow] + clickPoint.y)];
        }
        if (_delegate.textViewPasswordInput && !altPressed && !cmdPressed) {
            NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
            VT100GridCoord clickCoord = VT100GridCoordMake(clickPoint.x, clickPoint.y);
            VT100GridCoord cursorCoord = VT100GridCoordMake([_dataSource cursorX] - 1,
                                                            [_dataSource numberOfLines] - [_dataSource height] + [_dataSource cursorY] - 1);
            if (VT100GridCoordEquals(clickCoord, cursorCoord)) {
                [_delegate textViewDidSelectPasswordPrompt];
            }
        }
    } else if (isShiftedSingleClick && _findOnPageHelper.haveFindCursor && ![_selection hasSelection]) {
        VT100GridAbsCoord absCursor = [_findOnPageHelper findCursorAbsCoord];
        VT100GridCoord cursor = VT100GridCoordMake(absCursor.x,
                                                   absCursor.y - [_dataSource totalScrollbackOverflow]);
        [_selection beginSelectionAt:cursor
                                mode:kiTermSelectionModeCharacter
                              resume:NO
                              append:NO];
        NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
        [_selection moveSelectionEndpointTo:VT100GridCoordMake(clickPoint.x, clickPoint.y)];
        [_selection endLiveSelection];

        [_findOnPageHelper resetFindCursor];
    }

    DLog(@"Has selection=%@, delegate=%@", @([_selection hasSelection]), _delegate);
    if ([_selection hasSelection] && _delegate) {
        // if we want to copy our selection, do so
        DLog(@"selection copies text=%@", @([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]));
        if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
            [self copySelectionAccordingToUserPreferences];
        }
    }

    DLog(@"Mouse up. selection=%@", _selection);

    [_delegate refresh];
}

- (void)mouseMoved:(NSEvent *)event {
    [self resetMouseLocationToRefuseFirstResponderAt];
    URLAction *action = [self updateUnderlinedURLs:event];
    [self reportMouseEvent:event];
    [self updateCursor:event action:action];
}

- (void)mouseDragged:(NSEvent *)event
{
    [_altScreenMouseScrollInferer nonScrollWheelEvent:event];
    DLog(@"mouseDragged");
    if (_mouseDownIsThreeFingerClick) {
        DLog(@"is three finger click");
        return;
    }
    // Prevent accidental dragging while dragging semantic history item.
    BOOL dragThresholdMet = NO;
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint locationInTextView = [self convertPoint:locationInWindow fromView:nil];
    locationInTextView.x = ceil(locationInTextView.x);
    locationInTextView.y = ceil(locationInTextView.y);
    // Clamp the y position to be within the view. Sometimes we get events we probably shouldn't.
    locationInTextView.y = MIN(self.frame.size.height - 1,
                               MAX(0, locationInTextView.y));

    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
    int x = clickPoint.x;
    int y = clickPoint.y;

    NSPoint mouseDownLocation = [_mouseDownEvent locationInWindow];
    if (EuclideanDistance(mouseDownLocation, locationInWindow) >= kDragThreshold) {
        dragThresholdMet = YES;
    }
    if ([event eventNumber] == _firstMouseEventNumber) {
        // We accept first mouse for the purposes of focusing or dragging a
        // split pane but not for making a selection.
        return;
    }
    if (!dragOk_) {
        DLog(@"drag not ok");
        return;
    }

    if ([self reportMouseEvent:event]) {
        return;
    }
    [self removeUnderline];

    BOOL pressingCmdOnly = ([event modifierFlags] & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) == NSEventModifierFlagCommand;
    if (!pressingCmdOnly || dragThresholdMet) {
        DLog(@"mousedragged = yes");
        _mouseDragged = YES;
    }


    // It's ok to drag if Cmd is not required to be pressed or Cmd is pressed.
    BOOL okToDrag = (![iTermAdvancedSettingsModel requireCmdForDraggingText] ||
                     ([event modifierFlags] & NSEventModifierFlagCommand));
    if (okToDrag) {
        if (_mouseDownOnImage && dragThresholdMet) {
            [self _dragImage:_imageBeingClickedOn forEvent:event];
        } else if (_mouseDownOnSelection == YES && dragThresholdMet) {
            DLog(@"drag and drop a selection");
            // Drag and drop a selection
            NSString *theSelectedText = [self selectedText];
            if ([theSelectedText length] > 0) {
                [self _dragText:theSelectedText forEvent:event];
                DLog(@"Mouse drag. selection=%@", _selection);
                return;
            }
        }
    }

    if (pressingCmdOnly && !dragThresholdMet) {
        // If you're holding cmd (but not opt) then you're either trying to click on a link and
        // accidentally dragged a little bit, or you're trying to drag a selection. Do nothing until
        // the threshold is met.
        DLog(@"drag during cmd click");
        return;
    }
    if (_mouseDownOnSelection == YES &&
        ([event modifierFlags] & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) == (NSEventModifierFlagOption | NSEventModifierFlagCommand) &&
        !dragThresholdMet) {
        // Would be a drag of a rect region but mouse hasn't moved far enough yet. Prevent the
        // selection from changing.
        DLog(@"too-short drag of rect region");
        return;
    }

    if (![_selection hasSelection] && pressingCmdOnly && _semanticHistoryDragged == NO) {
        DLog(@"do semantic history check");
        // Only one Semantic History check per drag
        _semanticHistoryDragged = YES;

        // Drag a file handle (only possible when there is no selection).
        URLAction *action = [self urlActionForClickAtX:x y:y];
        NSString *path = action.fullPath;
        if (path == nil) {
            DLog(@"path is nil");
            return;
        }

        NSPoint dragPosition;
        NSImage *dragImage;

        dragImage = [[NSWorkspace sharedWorkspace] iconForFile:path];
        dragPosition = [self convertPoint:[event locationInWindow] fromView:nil];
        dragPosition.x -= [dragImage size].width / 2;

        NSURL *url = [NSURL fileURLWithPath:path];

        NSPasteboardItem *pbItem = [[[NSPasteboardItem alloc] init] autorelease];
        [pbItem setString:[url absoluteString] forType:(NSString *)kUTTypeFileURL];
        NSDraggingItem *dragItem = [[[NSDraggingItem alloc] initWithPasteboardWriter:pbItem] autorelease];
        [dragItem setDraggingFrame:NSMakeRect(dragPosition.x, dragPosition.y, dragImage.size.width, dragImage.size.height)
                          contents:dragImage];
        NSDraggingSession *draggingSession = [self beginDraggingSessionWithItems:@[ dragItem ]
                                                                           event:event
                                                                          source:self];

        draggingSession.animatesToStartingPositionsOnCancelOrFail = YES;
        draggingSession.draggingFormation = NSDraggingFormationNone;

        // Valid drag, so we reset the flag because mouseUp doesn't get called when a drag is done
        _semanticHistoryDragged = NO;
        DLog(@"did semantic history drag");

        return;

    }

    [_selectionScrollHelper mouseDraggedTo:locationInTextView coord:VT100GridCoordMake(x, y)];

    [self moveSelectionEndpointToX:x Y:y locationInTextView:locationInTextView];
}

#pragma mark PointerControllerDelegate

- (void)pasteFromClipboardWithEvent:(NSEvent *)event
{
    [self paste:nil];
}

- (void)pasteFromSelectionWithEvent:(NSEvent *)event
{
    [self pasteSelection:nil];
}

- (void)_openTargetWithEvent:(NSEvent *)event inBackground:(BOOL)openInBackground {
    // Command click in place.
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    int x = clickPoint.x;
    int y = clickPoint.y;
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    VT100GridCoord coord = VT100GridCoordMake(x, y);

    URLAction *action = [self urlActionForClickAtX:x y:y];
    DLog(@"openTargetWithEvent has action=%@", action);
    if (action) {
        switch (action.actionType) {
            case kURLActionOpenExistingFile: {
                NSString *extendedPrefix = [extractor wrappedStringAt:coord
                                                              forward:NO
                                                  respectHardNewlines:![self ignoreHardNewlinesInURLs]
                                                             maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                                    continuationChars:nil
                                                  convertNullsToSpace:YES
                                                               coords:nil];
                NSString *extendedSuffix = [extractor wrappedStringAt:coord
                                                              forward:YES
                                                  respectHardNewlines:![self ignoreHardNewlinesInURLs]
                                                             maxChars:[iTermAdvancedSettingsModel maxSemanticHistoryPrefixOrSuffix]
                                                    continuationChars:nil
                                                  convertNullsToSpace:YES
                                                               coords:nil];
                if (![self openSemanticHistoryPath:action.fullPath
                                     orRawFilename:action.rawFilename
                                  workingDirectory:action.workingDirectory
                                        lineNumber:action.lineNumber
                                      columnNumber:action.columnNumber
                                            prefix:extendedPrefix
                                            suffix:extendedSuffix]) {
                    [self findUrlInString:action.string andOpenInBackground:openInBackground];
                }
                break;
            }
            case kURLActionOpenURL: {
                NSURL *url = [NSURL URLWithUserSuppliedString:action.string];
                if ([url.scheme isEqualToString:@"file"] &&
                    url.host.length > 0 &&
                    ![url.host isEqualToString:[[iTermLocalHostNameGuesser sharedInstance] name]]) {
                    SCPPath *path = [[[SCPPath alloc] init] autorelease];
                    path.path = url.path;
                    path.hostname = url.host;
                    path.username = [PTYTextView usernameToDownloadFileOnHost:url.host];
                    if (path.username == nil) {
                        return;
                    }
                    [self downloadFileAtSecureCopyPath:path
                                           displayName:url.path.lastPathComponent
                                        locationInView:action.range.coordRange];
                } else {
                    [self openURL:url inBackground:openInBackground];
                }
                break;
            }

            case kURLActionSmartSelectionAction: {
                DLog(@"Run smart selection selector %@", NSStringFromSelector(action.selector));
                [self performSelector:action.selector withObject:action];
                break;
            }

            case kURLActionOpenImage:
                DLog(@"Open image");
                [[NSWorkspace sharedWorkspace] openFile:[(iTermImageInfo *)action.identifier nameForNewSavedTempFile]];
                break;

            case kURLActionSecureCopyFile:
                DLog(@"Secure copy file.");
                [self downloadFileAtSecureCopyPath:action.identifier
                                       displayName:action.string
                                    locationInView:action.range.coordRange];
                break;
        }
    }
}

- (BOOL)openSemanticHistoryPath:(NSString *)path
                  orRawFilename:(NSString *)rawFileName
               workingDirectory:(NSString *)workingDirectory
                     lineNumber:(NSString *)lineNumber
                   columnNumber:(NSString *)columnNumber
                         prefix:(NSString *)prefix
                         suffix:(NSString *)suffix {
    NSDictionary *subs = [self semanticHistorySubstitutionsWithPrefix:prefix
                                                               suffix:suffix
                                                                 path:path
                                                     workingDirectory:workingDirectory];
    return [self.semanticHistoryController openPath:path
                                      orRawFilename:rawFileName
                                      substitutions:subs
                                         lineNumber:lineNumber
                                       columnNumber:columnNumber];
}

- (NSDictionary *)semanticHistorySubstitutionsWithPrefix:(NSString *)prefix
                                                  suffix:(NSString *)suffix
                                                    path:(NSString *)path
                                        workingDirectory:(NSString *)workingDirectory {
    NSMutableDictionary *subs = [[[_delegate textViewVariables] mutableCopy] autorelease];
    NSDictionary *semanticHistorySubs =
        @{ kSemanticHistoryPrefixSubstitutionKey: [prefix stringWithEscapedShellCharactersIncludingNewlines:YES] ?: @"",
           kSemanticHistorySuffixSubstitutionKey: [suffix stringWithEscapedShellCharactersIncludingNewlines:YES] ?: @"",
           kSemanticHistoryPathSubstitutionKey: [path stringWithEscapedShellCharactersIncludingNewlines:YES] ?: @"",
           kSemanticHistoryWorkingDirectorySubstitutionKey: [workingDirectory stringWithEscapedShellCharactersIncludingNewlines:YES] ?: @"" };
    [subs addEntriesFromDictionary:semanticHistorySubs];
    return subs;
}

- (void)openTargetWithEvent:(NSEvent *)event {
    [self _openTargetWithEvent:event inBackground:NO];
}

- (void)openTargetInBackgroundWithEvent:(NSEvent *)event {
    [self _openTargetWithEvent:event inBackground:YES];
}

- (void)smartSelectWithEvent:(NSEvent *)event {
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    int x = clickPoint.x;
    int y = clickPoint.y;

    [self smartSelectAtX:x y:y ignoringNewlines:NO];
}

- (void)smartSelectAndMaybeCopyWithEvent:(NSEvent *)event
                        ignoringNewlines:(BOOL)ignoringNewlines {
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    int x = clickPoint.x;
    int y = clickPoint.y;

    [self smartSelectAtX:x y:y ignoringNewlines:ignoringNewlines];
    if ([_selection hasSelection] && _delegate) {
        // if we want to copy our selection, do so
        if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
            [self copySelectionAccordingToUserPreferences];
        }
    }
}

// Called for a right click that isn't control+click (e.g., two fingers on trackpad).
- (void)openContextMenuWithEvent:(NSEvent *)event {
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    openingContextMenu_ = YES;

    // Slowly moving away from using NSPoint for integer coordinates.
    _validationClickPoint = VT100GridCoordMake(clickPoint.x, clickPoint.y);
    NSMenu *menu = [self contextMenuWithEvent:event];
    menu.delegate = self;
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
    _validationClickPoint = VT100GridCoordMake(-1, -1);
    openingContextMenu_ = NO;
}

- (NSMenu *)contextMenuWithEvent:(NSEvent *)event {
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    int x = clickPoint.x;
    int y = clickPoint.y;
    NSMenu *markMenu = nil;
    VT100ScreenMark *mark = [_dataSource markOnLine:y];
    DLog(@"contextMenuWithEvent:%@ x=%d, mark=%@, mark command=%@", event, x, mark, [mark command]);
    if (mark && mark.command.length) {
        markMenu = [self menuForMark:mark directory:[_dataSource workingDirectoryOnLine:y]];
        NSPoint locationInWindow = [event locationInWindow];
        if (locationInWindow.x < [iTermAdvancedSettingsModel terminalMargin]) {
            return markMenu;
        }
    }

    VT100GridCoord coord = VT100GridCoordMake(x, y);
    iTermImageInfo *imageInfo = [self imageInfoAtCoord:coord];

    const BOOL clickedInExistingSelection = [_selection containsCoord:VT100GridCoordMake(x, y)];
    if (!imageInfo &&
        !clickedInExistingSelection) {
        // Didn't click on selection.
        // Save the selection and do a smart selection. If we don't like the result, restore it.
        iTermSelection *savedSelection = [[_selection copy] autorelease];
        [self smartSelectWithEvent:event];
        NSCharacterSet *nonWhiteSpaceSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
        NSString *text = [self selectedText];
        if (!text ||
            !text.length ||
            [text rangeOfCharacterFromSet:nonWhiteSpaceSet].location == NSNotFound) {
            // If all we selected was white space, undo it.
            [_selection release];
            _selection = [savedSelection retain];
            self.savedSelectedText = [self selectedText];
        } else {
            self.savedSelectedText = text;
        }
    } else if (clickedInExistingSelection && [self _haveShortSelection]) {
        self.savedSelectedText = [self selectedText];
    }
    [self setNeedsDisplay:YES];
    NSMenu *contextMenu = [self menuAtCoord:coord];
    if (markMenu) {
        NSMenuItem *markItem = [[[NSMenuItem alloc] initWithTitle:@"Command Info"
                                                           action:nil
                                                    keyEquivalent:@""] autorelease];
        markItem.submenu = markMenu;
        [contextMenu insertItem:markItem atIndex:0];
        [contextMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    }

    return contextMenu;
}

- (void)extendSelectionWithEvent:(NSEvent *)event {
    if ([_selection hasSelection]) {
        NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
        [_selection beginExtendingSelectionAt:VT100GridCoordMake(clickPoint.x, clickPoint.y)];
        [_selection endLiveSelection];
        if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
            [self copySelectionAccordingToUserPreferences];
        }
    }
}

- (void)showDefinitionForWordAt:(NSPoint)clickPoint {
    if (clickPoint.y < 0) {
        return;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    VT100GridWindowedRange range =
        [extractor rangeForWordAt:VT100GridCoordMake(clickPoint.x, clickPoint.y)
                    maximumLength:kReasonableMaximumWordLength];
    NSAttributedString *word = [extractor contentInRange:range
                                       attributeProvider:^NSDictionary *(screen_char_t theChar) {
                                           return [self charAttributes:theChar];
                                       }
                                              nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                                     pad:NO
                                      includeLastNewline:NO
                                  trimTrailingWhitespace:YES
                                            cappedAtSize:_dataSource.width
                                            truncateTail:YES
                                       continuationChars:nil
                                                  coords:nil];
    if (word.length) {
        NSPoint point = [self pointForCoord:range.coordRange.start];
        point.y += _lineHeight;
        NSDictionary *attributes = [word attributesAtIndex:0 effectiveRange:nil];
        if (attributes[NSFontAttributeName]) {
            NSFont *font = attributes[NSFontAttributeName];
            point.y += font.descender;
        }
        [self showDefinitionForAttributedString:word
                                        atPoint:point];
    }
}

- (BOOL)showWebkitPopoverAtPoint:(NSPoint)pointInWindow url:(NSURL *)url {
    WKWebView *webView = [[iTermWebViewFactory sharedInstance] webView];
    if (webView) {
        if ([[url.scheme lowercaseString] isEqualToString:@"http"]) {
            [webView loadHTMLString:@"This site cannot be displayed in QuickLook because of Application Transport Security. Only HTTPS URLs can be previewed." baseURL:nil];
        } else {
            NSURLRequest *request =
                [[[NSURLRequest alloc] initWithURL:url] autorelease];
            [webView loadRequest:request];
        }
        NSPopover *popover = [[[NSPopover alloc] init] autorelease];
        NSViewController *viewController = [[[iTermWebViewWrapperViewController alloc] initWithWebView:webView
                                                                                             backupURL:url] autorelease];
        popover.contentViewController = viewController;
        popover.contentSize = viewController.view.frame.size;
        NSRect rect = NSMakeRect(pointInWindow.x - _charWidth / 2,
                                 pointInWindow.y - _lineHeight / 2,
                                 _charWidth,
                                 _lineHeight);
        rect = [self convertRect:rect fromView:nil];
        popover.behavior = NSPopoverBehaviorSemitransient;
        popover.delegate = self;
        [popover showRelativeToRect:rect
                             ofView:self
                      preferredEdge:NSRectEdgeMinY];
        return YES;
    } else {
        return NO;
    }
}


- (void)quickLookWithEvent:(NSEvent *)event {
    DLog(@"Quick look with event %@\n%@", event, [NSThread callStackSymbols]);
    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:YES];
    URLAction *urlAction = [self urlActionForClickAtX:clickPoint.x y:clickPoint.y];
    if (!urlAction && [iTermAdvancedSettingsModel performDictionaryLookupOnQuickLook]) {
        [self showDefinitionForWordAt:clickPoint];
        return;
    }
    NSURL *url = nil;
    switch (urlAction.actionType) {
        case kURLActionSecureCopyFile:
            url = [urlAction.identifier URL];
            break;

        case kURLActionOpenExistingFile:
            url = [NSURL fileURLWithPath:urlAction.fullPath];
            break;

        case kURLActionOpenImage:
            url = [NSURL fileURLWithPath:[urlAction.identifier nameForNewSavedTempFile]];
            break;

        case kURLActionOpenURL: {
            if (!urlAction.string) {
                break;
            }
            url = [NSURL URLWithUserSuppliedString:urlAction.string];
            if (url && [self showWebkitPopoverAtPoint:event.locationInWindow url:url]) {
                return;
            }
            break;
        }

        case kURLActionSmartSelectionAction:
            break;
    }

    if (url) {
        NSPoint windowPoint = event.locationInWindow;
        NSRect windowRect = NSMakeRect(windowPoint.x - _charWidth / 2,
                                       windowPoint.y - _lineHeight / 2,
                                       _charWidth,
                                       _lineHeight);

        NSRect screenRect = [self.window convertRectToScreen:windowRect];
        self.quickLookController = [[[iTermQuickLookController alloc] init] autorelease];
        [self.quickLookController addURL:url];
        [self.quickLookController showWithSourceRect:screenRect controller:self.window.delegate];
    }
}

- (void)nextTabWithEvent:(NSEvent *)event
{
    [_delegate textViewSelectNextTab];
}

- (void)previousTabWithEvent:(NSEvent *)event
{
    [_delegate textViewSelectPreviousTab];
}

- (void)nextWindowWithEvent:(NSEvent *)event
{
    [_delegate textViewSelectNextWindow];
}

- (void)previousWindowWithEvent:(NSEvent *)event
{
    [_delegate textViewSelectPreviousWindow];
}

- (void)movePaneWithEvent:(NSEvent *)event
{
    [self movePane:nil];
}

- (void)sendEscapeSequence:(NSString *)text withEvent:(NSEvent *)event
{
    [_delegate sendEscapeSequence:text];
}

- (void)sendHexCode:(NSString *)codes withEvent:(NSEvent *)event
{
    [_delegate sendHexCode:codes];
}

- (void)sendText:(NSString *)text withEvent:(NSEvent *)event
{
    [_delegate sendText:text];
}

- (void)selectPaneLeftWithEvent:(NSEvent *)event
{
    [_delegate selectPaneLeftInCurrentTerminal];
}

- (void)selectPaneRightWithEvent:(NSEvent *)event
{
    [_delegate selectPaneRightInCurrentTerminal];
}

- (void)selectPaneAboveWithEvent:(NSEvent *)event
{
    [_delegate selectPaneAboveInCurrentTerminal];
}

- (void)selectPaneBelowWithEvent:(NSEvent *)event
{
    [_delegate selectPaneBelowInCurrentTerminal];
}

- (void)newWindowWithProfile:(NSString *)guid withEvent:(NSEvent *)event
{
    [_delegate textViewCreateWindowWithProfileGuid:guid];
}

- (void)newTabWithProfile:(NSString *)guid withEvent:(NSEvent *)event
{
    [_delegate textViewCreateTabWithProfileGuid:guid];
}

- (void)newVerticalSplitWithProfile:(NSString *)guid withEvent:(NSEvent *)event
{
    [_delegate textViewSplitVertically:YES withProfileGuid:guid];
}

- (void)newHorizontalSplitWithProfile:(NSString *)guid withEvent:(NSEvent *)event
{
    [_delegate textViewSplitVertically:NO withProfileGuid:guid];
}

- (void)selectNextPaneWithEvent:(NSEvent *)event
{
    [_delegate textViewSelectNextPane];
}

- (void)selectPreviousPaneWithEvent:(NSEvent *)event
{
    [_delegate textViewSelectPreviousPane];
}

- (VT100GridCoord)moveCursorHorizontallyTo:(VT100GridCoord)target from:(VT100GridCoord)cursor {
    DLog(@"Moving cursor horizontally from %@ to %@",
         VT100GridCoordDescription(cursor), VT100GridCoordDescription(target));
    VT100Terminal *terminal = [_dataSource terminal];
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    NSComparisonResult initialOrder = VT100GridCoordOrder(cursor, target);
    // Note that we could overshoot the destination because of double-width characters if the target
    // is a DWC_RIGHT.
    while (![extractor coord:cursor isEqualToCoord:target]) {
        switch (initialOrder) {
            case NSOrderedAscending:
                [_delegate writeStringWithLatin1Encoding:[[terminal.output keyArrowRight:0] stringWithEncoding:NSISOLatin1StringEncoding]];
                cursor = [extractor successorOfCoord:cursor];
                break;

            case NSOrderedDescending:
                [_delegate writeStringWithLatin1Encoding:[[terminal.output keyArrowLeft:0] stringWithEncoding:NSISOLatin1StringEncoding]];
                cursor = [extractor predecessorOfCoord:cursor];
                break;

            case NSOrderedSame:
                return cursor;
        }
    }
    DLog(@"Cursor will move to %@", VT100GridCoordDescription(cursor));
    return cursor;
}

- (void)placeCursorOnCurrentLineWithEvent:(NSEvent *)event verticalOk:(BOOL)verticalOk {
    DLog(@"PTYTextView placeCursorOnCurrentLineWithEvent BEGIN %@", event);

    NSPoint clickPoint = [self clickPoint:event allowRightMarginOverflow:NO];
    VT100GridCoord target = VT100GridCoordMake(clickPoint.x, clickPoint.y);
    VT100Terminal *terminal = [_dataSource terminal];

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
            [_delegate writeStringWithLatin1Encoding:[[terminal.output keyArrowUp:0] stringWithEncoding:NSISOLatin1StringEncoding]];
            cursor.y--;
        } else {
            [_delegate writeStringWithLatin1Encoding:[[terminal.output keyArrowDown:0] stringWithEncoding:NSISOLatin1StringEncoding]];
            cursor.y++;
        }
    }

    if (cursor.x != target.x) {
        [self moveCursorHorizontallyTo:target from:cursor];
    }

    DLog(@"PTYTextView placeCursorOnCurrentLineWithEvent END");
}

- (VT100GridCoordRange)rangeByTrimmingNullsFromRange:(VT100GridCoordRange)range
                                          trimSpaces:(BOOL)trimSpaces
{
    VT100GridCoordRange result = range;
    int width = [_dataSource width];
    int lineY = result.start.y;
    screen_char_t *line = [_dataSource getLineAtIndex:lineY];
    while (!VT100GridCoordEquals(result.start, range.end)) {
        if (lineY != result.start.y) {
            lineY = result.start.y;
            line = [_dataSource getLineAtIndex:lineY];
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
            line = [_dataSource getLineAtIndex:y];
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

- (IBAction)installShellIntegration:(id)sender {
    iTermWarning *warning = [[[iTermWarning alloc] init] autorelease];
    warning.title = @"Shell Integration comes with an optional Utilities Package, which lets you view images and download files. What would you prefer?";
    warning.actionLabels = @[ @"Install Shell Integration & Utilities", @"Cancel", @"Shell Integration Only" ];
    warning.identifier = @"NoSyncInstallUtilitiesPackage";
    warning.warningType = kiTermWarningTypePermanentlySilenceable;
    warning.cancelLabel = @"Cancel";
    warning.window = self.window;
    warning.showHelpBlock = ^() {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/utilities.html"]];
    };

    NSString *theCommand = nil;
    switch ([warning runModal]) {
        case kiTermWarningSelection0:
            theCommand = @"curl -L https://iterm2.com/shell_integration/install_shell_integration_and_utilities.sh | bash\n";
            break;
        case kiTermWarningSelection1:
            return;
        case kiTermWarningSelection2:
            theCommand = @"curl -L https://iterm2.com/shell_integration/install_shell_integration.sh | bash\n";
            break;
        case kItermWarningSelectionError:
            assert(false);
    }
    if (theCommand) {
        [self installShellIntegrationWithCommand:theCommand];
    } else {
        assert(false);
    }
}

- (void)installShellIntegrationWithCommand:(NSString *)theCommand {
    iTermWarning *warning = [[[iTermWarning alloc] init] autorelease];
    warning.title = [NSString stringWithFormat:@"Ok to run this command in the current shell?\n\n%@", theCommand];
    warning.warningActions =
    @[
          [iTermWarningAction warningActionWithLabel:@"OK" block:^(iTermWarningSelection selection) {
              [_delegate writeTask:theCommand];
          }],
          [iTermWarningAction warningActionWithLabel:@"Cancel" block:nil]
      ];
    warning.identifier = @"NoSyncConfirmShellIntegrationCommand";
    warning.warningType = kiTermWarningTypePermanentlySilenceable;
    warning.cancelLabel = @"Cancel";
    warning.window = self.window;
    [warning runModal];
}

- (IBAction)selectAll:(id)sender
{
    // Set the selection region to the whole text.
    [_selection beginSelectionAt:VT100GridCoordMake(0, 0)
                            mode:kiTermSelectionModeCharacter
                          resume:NO
                          append:NO];
    [_selection moveSelectionEndpointTo:VT100GridCoordMake([_dataSource width],
                                                           [_dataSource numberOfLines] - 1)];
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

    VT100GridCoord relativeStart =
        VT100GridCoordMake(range.start.x,
                           MAX(0, range.start.y - [_dataSource totalScrollbackOverflow]));
    VT100GridCoord relativeEnd =
        VT100GridCoordMake(range.end.x,
                           MAX(0, range.end.y - [_dataSource totalScrollbackOverflow]));

    DLog(@"The relative range is %@ to %@",
         VT100GridCoordDescription(relativeStart), VT100GridCoordDescription(relativeEnd));
    [_selection beginSelectionAt:relativeStart
                            mode:kiTermSelectionModeCharacter
                          resume:NO
                          append:NO];
    [_selection moveSelectionEndpointTo:relativeEnd];
    [_selection endLiveSelection];
    DLog(@"Done selecting output of last command.");

    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (void)deselect
{
    [_selection endLiveSelection];
    [_selection clearSelection];
}

- (NSString *)selectedText {
    if (_savedSelectedText) {
        DLog(@"Returning saved selected text");
        return _savedSelectedText;
    }
    return [self selectedTextCappedAtSize:0];
}

- (NSString *)selectedTextCappedAtSize:(int)maxBytes {
    return [self selectedTextAttributed:NO cappedAtSize:maxBytes minimumLineNumber:0];
}

// Does not include selected text on lines before |minimumLineNumber|.
// Returns an NSAttributedString* if |attributed|, or an NSString* if not.
- (id)selectedTextAttributed:(BOOL)attributed
                cappedAtSize:(int)maxBytes
           minimumLineNumber:(int)minimumLineNumber {
    if (![_selection hasSelection]) {
        DLog(@"startx < 0 so there is no selected text");
        return nil;
    }
    BOOL copyLastNewline = [iTermPreferences boolForKey:kPreferenceKeyCopyLastNewline];
    BOOL trimWhitespace = [iTermAdvancedSettingsModel trimWhitespaceOnCopy];
    id theSelectedText;
    NSDictionary *(^attributeProvider)(screen_char_t);
    if (attributed) {
        theSelectedText = [[[NSMutableAttributedString alloc] init] autorelease];
        attributeProvider = ^NSDictionary *(screen_char_t theChar) {
            return [self charAttributes:theChar];
        };
    } else {
        theSelectedText = [[[NSMutableString alloc] init] autorelease];
        attributeProvider = nil;
    }

    [_selection enumerateSelectedRanges:^(VT100GridWindowedRange range, BOOL *stop, BOOL eol) {
        if (range.coordRange.end.y < minimumLineNumber) {
            return;
        } else {
            range.coordRange.start.y = MAX(range.coordRange.start.y, minimumLineNumber);
        }
        int cap = INT_MAX;
        if (maxBytes > 0) {
            cap = maxBytes - [theSelectedText length];
            if (cap <= 0) {
                cap = 0;
                *stop = YES;
            }
        }
        if (cap != 0) {
            iTermTextExtractor *extractor =
                [iTermTextExtractor textExtractorWithDataSource:_dataSource];
            id content = [extractor contentInRange:range
                                 attributeProvider:attributeProvider
                                        nullPolicy:kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal
                                               pad:NO
                                includeLastNewline:copyLastNewline
                            trimTrailingWhitespace:trimWhitespace
                                      cappedAtSize:cap
                                      truncateTail:YES
                                 continuationChars:nil
                                            coords:nil];
            if (attributed) {
                [theSelectedText appendAttributedString:content];
            } else {
                [theSelectedText appendString:content];
            }
            NSString *contentString = attributed ? [content string] : content;
            if (eol && ![contentString hasSuffix:@"\n"]) {
                if (attributed) {
                    [theSelectedText iterm_appendString:@"\n"];
                } else {
                    [theSelectedText appendString:@"\n"];
                }
            }
        }
    }];
    return theSelectedText;
}

- (NSString *)selectedTextWithCappedAtSize:(int)maxBytes
                         minimumLineNumber:(int)minimumLineNumber {
    return [self selectedTextAttributed:NO
                           cappedAtSize:maxBytes
                      minimumLineNumber:minimumLineNumber];
}

- (NSAttributedString *)selectedAttributedTextWithPad:(BOOL)pad {
    return [self selectedTextAttributed:YES cappedAtSize:0 minimumLineNumber:0];
}

- (NSAttributedString *)attributedContent {
    return [self contentWithAttributes:YES];
}

- (NSString *)content {
    return [self contentWithAttributes:NO];
}

- (id)contentWithAttributes:(BOOL)attributes {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    VT100GridCoordRange theRange = VT100GridCoordRangeMake(0,
                                                           0,
                                                           [_dataSource width],
                                                           [_dataSource numberOfLines] - 1);
    NSDictionary *(^attributeProvider)(screen_char_t) = nil;
    if (attributes) {
        attributeProvider =^NSDictionary *(screen_char_t theChar) {
            return [self charAttributes:theChar];
        };
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

- (void)splitTextViewVertically:(id)sender {
    [_delegate textViewSplitVertically:YES withProfileGuid:nil];
}

- (void)splitTextViewHorizontally:(id)sender {
    [_delegate textViewSplitVertically:NO withProfileGuid:nil];
}

- (void)movePane:(id)sender
{
    [_delegate textViewMovePane];
}

- (void)swapSessions:(id)sender {
    [_delegate textViewSwapPane];
}

- (void)clearTextViewBuffer:(id)sender
{
    [_dataSource clearBuffer];
}

- (void)addViewForNote:(PTYNoteViewController *)note
{
    // Make sure scrollback overflow is reset.
    [self refresh];
    [note.view removeFromSuperview];
    [self addSubview:note.view];
    [self updateNoteViewFrames];
    [note setNoteHidden:NO];
}


- (void)addNote:(id)sender
{
    if ([_selection hasSelection]) {
        PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
        [_dataSource addNote:note inRange:_selection.lastRange.coordRange];

        // Make sure scrollback overflow is reset.
        [self refresh];
        [note.view removeFromSuperview];
        [self addSubview:note.view];
        [self updateNoteViewFrames];
        [note setNoteHidden:NO];
        [note beginEditing];
    }
}

- (void)downloadWithSCP:(id)sender
{
    if (![_selection hasSelection]) {
        return;
    }
    SCPPath *scpPath = nil;
    NSString *selectedText = [[self selectedText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *parts = [selectedText componentsSeparatedByString:@"\n"];
    if (parts.count != 1) {
        return;
    }
    scpPath = [_dataSource scpPathForFile:parts[0] onLine:_selection.lastRange.coordRange.start.y];
    VT100GridCoordRange range = _selection.lastRange.coordRange;

    [self downloadFileAtSecureCopyPath:scpPath displayName:selectedText locationInView:range];
}

- (void)downloadFileAtSecureCopyPath:(SCPPath *)scpPath
                         displayName:(NSString *)name
                      locationInView:(VT100GridCoordRange)range {
    [_delegate startDownloadOverSCP:scpPath];

    NSDictionary *attributes =
        @{ NSForegroundColorAttributeName: [self selectedTextColor],
           NSBackgroundColorAttributeName: [self selectionBackgroundColor],
           NSFontAttributeName: _primaryFont.font };
    NSSize size = [name sizeWithAttributes:attributes];
    size.height = _lineHeight;
    NSImage* image = [[[NSImage alloc] initWithSize:size] autorelease];
    [image lockFocus];
    [name drawAtPoint:NSMakePoint(0, 0) withAttributes:attributes];
    [image unlockFocus];

    NSRect windowRect = [self convertRect:NSMakeRect(range.start.x * _charWidth + [iTermAdvancedSettingsModel terminalMargin],
                                                     range.start.y * _lineHeight,
                                                     0,
                                                     0)
                                   toView:nil];
    NSPoint point = [[self window] convertRectToScreen:windowRect].origin;
    point.y -= _lineHeight;
    [[FileTransferManager sharedInstance] animateImage:image
                            intoDownloadsMenuFromPoint:point
                                              onScreen:[[self window] screen]];
}

- (void)showNotes:(id)sender
{
    for (PTYNoteViewController *note in [_dataSource notesInRange:VT100GridCoordRangeMake(_validationClickPoint.x,
                                                                                          _validationClickPoint.y,
                                                                                          _validationClickPoint.x + 1,
                                                                                          _validationClickPoint.y)]) {
        [note setNoteHidden:NO];
    }
}

- (void)updateNoteViewFrames
{
    for (NSView *view in [self subviews]) {
        if ([view isKindOfClass:[PTYNoteView class]]) {
            PTYNoteView *noteView = (PTYNoteView *)view;
            PTYNoteViewController *note =
                (PTYNoteViewController *)noteView.delegate.noteViewController;
            VT100GridCoordRange coordRange = [_dataSource coordRangeOfNote:note];
            if (coordRange.end.y >= 0) {
                [note setAnchor:NSMakePoint(coordRange.end.x * _charWidth + [iTermAdvancedSettingsModel terminalMargin],
                                            (1 + coordRange.end.y) * _lineHeight)];
            }
        }
    }
    [_dataSource removeInaccessibleNotes];
}

- (void)editTextViewSession:(id)sender
{
    [_delegate textViewEditSession];
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

- (void)toggleBroadcastingInput:(id)sender
{
    [_delegate textViewToggleBroadcastingInput];
}

- (void)closeTextViewSession:(id)sender {
    [_delegate textViewCloseWithConfirmation];
}

- (void)restartTextViewSession:(id)sender {
    [_delegate textViewRestartWithConfirmation];
}

- (void)copySelectionAccordingToUserPreferences {
    DLog(@"copySelectionAccordingToUserPreferences");
    if ([iTermAdvancedSettingsModel copyWithStylesByDefault]) {
        [self copyWithStyles:self];
    } else {
        [self copy:self];
    }
}

- (void)copy:(id)sender {
    // TODO: iTermSelection should use absolute coordinates everywhere. Until that is done, we must
    // call refresh here to take care of any scrollback overflow that would cause the selected range
    // to not match reality.
    [self refresh];

    DLog(@"-[PTYTextView copy:] called");
    NSString *copyString = [self selectedText];

    if ([iTermAdvancedSettingsModel disallowCopyEmptyString] && copyString.length == 0) {
        DLog(@"Disallow copying empty string");
        return;
    }
    DLog(@"Have selected text of length %d. selection=%@", (int)[copyString length], _selection);
    if (copyString) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
        [pboard setString:copyString forType:NSStringPboardType];
    }

    [[PasteboardHistory sharedInstance] save:copyString];
}

- (IBAction)copyWithStyles:(id)sender {
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];

    DLog(@"-[PTYTextView copyWithStyles:] called");
    NSAttributedString *copyAttributedString = [self selectedAttributedTextWithPad:NO];
    if ([iTermAdvancedSettingsModel disallowCopyEmptyString] &&
        copyAttributedString.length == 0) {
        DLog(@"Disallow copying empty string");
        return;
    }

    DLog(@"Have selected text of length %d. selection=%@", (int)[copyAttributedString length], _selection);
    NSMutableArray *types = [NSMutableArray array];
    if (copyAttributedString) {
        [types addObject:NSRTFPboardType];
    }
    [pboard declareTypes:types owner:self];
    if (copyAttributedString) {
        // I used to convert this to RTF data using
        // RTFFromRange:documentAttributes: but images wouldn't paste right.
        [pboard clearContents];
        [pboard writeObjects:@[ copyAttributedString ]];
    }
    // I used to do
    //   [pboard setString:[copyAttributedString string] forType:NSStringPboardType]
    // but this seems to take precedence over the attributed version for
    // pasting sometimes, for example in TextEdit.
    [[PasteboardHistory sharedInstance] save:[copyAttributedString string]];
}

// Returns a dictionary to pass to NSAttributedString.
- (NSDictionary *)charAttributes:(screen_char_t)c
{
    BOOL isBold = c.bold;
    BOOL isFaint = c.faint;
    NSColor *fgColor = [self colorForCode:c.foregroundColor
                                    green:c.fgGreen
                                     blue:c.fgBlue
                                colorMode:c.foregroundColorMode
                                     bold:isBold
                                    faint:isFaint
                             isBackground:NO];
    NSColor *bgColor = [self colorForCode:c.backgroundColor
                                    green:c.bgGreen
                                     blue:c.bgBlue
                                colorMode:c.backgroundColorMode
                                     bold:NO
                                    faint:NO
                             isBackground:YES];
    fgColor = [fgColor colorByPremultiplyingAlphaWithColor:bgColor];

    int underlineStyle = (c.urlCode || c.underline) ? (NSUnderlineStyleSingle | NSUnderlineByWord) : 0;

    BOOL isItalic = c.italic;
    PTYFontInfo *fontInfo = [self getFontForChar:c.code
                                       isComplex:c.complexChar
                                      renderBold:&isBold
                                    renderItalic:&isItalic];
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraphStyle.lineBreakMode = NSLineBreakByCharWrapping;

    NSFont *font = fontInfo.font;
    if (!font) {
        // Ordinarily fontInfo would never be nil, but it is in unit tests. It's useful to distinguish
        // bold from regular in tests, so we ensure that attribute is correctly set in this test-only
        // path.
        const CGFloat size = [NSFont systemFontSize];
        if (c.bold) {
            font = [NSFont boldSystemFontOfSize:size];
        } else {
            font = [NSFont systemFontOfSize:size];
        }
    }
    NSDictionary *attributes = @{ NSForegroundColorAttributeName: fgColor,
                                  NSBackgroundColorAttributeName: bgColor,
                                  NSFontAttributeName: font,
                                  NSParagraphStyleAttributeName: paragraphStyle,
                                  NSUnderlineStyleAttributeName: @(underlineStyle) };
    if ([iTermAdvancedSettingsModel excludeBackgroundColorsFromCopiedStyle]) {
        attributes = [attributes dictionaryByRemovingObjectForKey:NSBackgroundColorAttributeName];
    }
    if (c.urlCode) {
        NSURL *url = [[iTermURLStore sharedInstance] urlForCode:c.urlCode];
        if (url != nil) {
            attributes = [attributes dictionaryBySettingObject:url forKey:NSLinkAttributeName];
        }
    }

    return attributes;
}

- (void)paste:(id)sender
{
    DLog(@"Checking if delegate %@ can paste", _delegate);
    if ([_delegate respondsToSelector:@selector(paste:)]) {
        DLog(@"Calling paste on delegate.");
        [_delegate paste:sender];
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

- (BOOL)_broadcastToggleable
{
    // There used to be a restriction that you could not toggle broadcasting on
    // the current session if no others were on, but that broke the feature for
    // focus-follows-mouse users. This is an experiment to see if removing that
    // restriction works. 9/8/12
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([item action] == @selector(paste:)) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        // Check if there is a string type on the pasteboard
        if ([pboard stringForType:NSStringPboardType] != nil) {
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
    if ([item action]==@selector(toggleBroadcastingInput:) &&
        [self _broadcastToggleable]) {
        return YES;
    }
    if ([item action] == @selector(showHideNotes:)) {
        item.state = [self anyAnnotationsAreVisible] ? NSOnState : NSOffState;
        return YES;
    }
    if ([item action] == @selector(toggleShowTimestamps:)) {
        item.state = _drawingHelper.showTimestamps ? NSOnState : NSOffState;
        return YES;
    }

    if ([item action]==@selector(saveDocumentAs:)) {
        return [self isAnyCharSelected];
    } else if ([item action] == @selector(selectAll:) ||
               [item action]==@selector(splitTextViewVertically:) ||
               [item action]==@selector(splitTextViewHorizontally:) ||
               [item action]==@selector(clearTextViewBuffer:) ||
               [item action]==@selector(editTextViewSession:) ||
               [item action]==@selector(closeTextViewSession:) ||
               [item action]==@selector(movePane:) ||
               [item action]==@selector(swapSessions:) ||
               [item action]==@selector(installShellIntegration:) ||
               ([item action] == @selector(print:) && [item tag] != 1)) {
        // We always validate the above commands
        return YES;
    }
    if ([item action]==@selector(restartTextViewSession:)) {
        return [_delegate isRestartable];
    } else if ([item action]==@selector(bury:)) {
        return YES;
    }

    if ([item action]==@selector(mail:) ||
        [item action]==@selector(browse:) ||
        [item action]==@selector(searchInBrowser:) ||
        [item action]==@selector(addNote:) ||
        [item action]==@selector(copy:) ||
        [item action]==@selector(copyWithStyles:) ||
        ([item action]==@selector(print:) && [item tag] == 1)) { // print selection
        // These commands are allowed only if there is a selection.
        return [_selection hasSelection];
    } else if ([item action]==@selector(pasteSelection:)) {
        return [[iTermController sharedInstance] lastSelection] != nil;
    } else if ([item action]==@selector(selectOutputOfLastCommand:)) {
        return [_delegate textViewCanSelectOutputOfLastCommand];
    } else if ([item action]==@selector(selectCurrentCommand:)) {
        return [_delegate textViewCanSelectCurrentCommand];
    }
    if ([item action] == @selector(downloadWithSCP:)) {
        return ([self _haveShortSelection] &&
                [_selection hasSelection] &&
                [_dataSource scpPathForFile:[self selectedText]
                                     onLine:_selection.lastRange.coordRange.start.y] != nil);
    }
    if ([item action]==@selector(showNotes:)) {
        return _validationClickPoint.x >= 0 &&
               [[_dataSource notesInRange:VT100GridCoordRangeMake(_validationClickPoint.x,
                                                                  _validationClickPoint.y,
                                                                  _validationClickPoint.x + 1,
                                                                  _validationClickPoint.y)] count] > 0;
    }

    // Image actions
    if ([item action] == @selector(saveImageAs:) ||
        [item action] == @selector(copyImage:) ||
        [item action] == @selector(openImage:) ||
        [item action] == @selector(togglePauseAnimatingImage:) ||
        [item action] == @selector(inspectImage:)) {
        return YES;
    }
    if ([item action] == @selector(reRunCommand:)) {
        return YES;
    }
    if ([item action] == @selector(selectCommandOutput:)) {
        return [_dataSource textViewRangeOfOutputForCommandMark:[item representedObject]].start.x != -1;
    }
    if ([item action] == @selector(pasteBase64Encoded:)) {
        return [[NSPasteboard generalPasteboard] dataForFirstFile] != nil;
    }

    if (item.action == @selector(terminalStateToggleAlternateScreen:) ||
        item.action == @selector(terminalStateToggleFocusReporting:) ||
        item.action == @selector(terminalStateToggleMouseReporting:) ||
        item.action == @selector(terminalStateTogglePasteBracketing:) ||
        item.action == @selector(terminalStateToggleApplicationCursor:) ||
        item.action == @selector(terminalStateToggleApplicationKeypad:)) {
        item.state = [self.delegate textViewTerminalStateForMenuItem:item] ? NSOnState : NSOffState;
        return YES;
    }
    if (item.action == @selector(terminalStateReset:)) {
        return YES;
    }

    SEL theSel = [item action];
    if ([NSStringFromSelector(theSel) hasPrefix:@"contextMenuAction"]) {
        return YES;
    }
    return NO;
}

- (IBAction)terminalStateToggleAlternateScreen:(id)sender {
    [self.delegate textViewToggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleFocusReporting:(id)sender {
    [self.delegate textViewToggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleMouseReporting:(id)sender {
    [self.delegate textViewToggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateTogglePasteBracketing:(id)sender {
    [self.delegate textViewToggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleApplicationCursor:(id)sender {
    [self.delegate textViewToggleTerminalStateForMenuItem:sender];
}
- (IBAction)terminalStateToggleApplicationKeypad:(id)sender {
    [self.delegate textViewToggleTerminalStateForMenuItem:sender];
}

- (IBAction)terminalStateReset:(id)sender {
    [self.delegate textViewResetTerminal];
}

- (BOOL)_haveShortSelection
{
    int width = [_dataSource width];
    return [_selection hasSelection] && [_selection length] <= width;
}

- (NSDictionary<NSNumber *, NSString *> *)smartSelectionActionSelectorDictionary {
    // The selector's name must begin with contextMenuAction to
    // pass validateMenuItem.
    return @{ @(kOpenFileContextMenuAction): NSStringFromSelector(@selector(contextMenuActionOpenFile:)),
              @(kOpenUrlContextMenuAction): NSStringFromSelector(@selector(contextMenuActionOpenURL:)),
              @(kRunCommandContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCommand:)),
              @(kRunCoprocessContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCoprocess:)),
              @(kSendTextContextMenuAction): NSStringFromSelector(@selector(contextMenuActionSendText:)),
              @(kRunCommandInWindowContextMenuAction): NSStringFromSelector(@selector(contextMenuActionRunCommandInWindow:)) };
}

- (SEL)selectorForSmartSelectionAction:(NSDictionary *)action {
    NSDictionary<NSNumber *, NSString *> *dictionary = [self smartSelectionActionSelectorDictionary];
    ContextMenuActions contextMenuAction = [ContextMenuActionPrefsController actionForActionDict:action];
    return NSSelectorFromString(dictionary[@(contextMenuAction)]);
}

- (BOOL)addCustomActionsToMenu:(NSMenu *)theMenu matchingText:(NSString *)textWindow line:(int)line {
    BOOL didAdd = NO;
    NSArray *rulesArray = _smartSelectionRules ? _smartSelectionRules : [SmartSelectionController defaultRules];
    const int numRules = [rulesArray count];

    DLog(@"Looking for custom actions. Evaluating smart selection rules…");
    DLog(@"text window is: %@", textWindow);
    for (int j = 0; j < numRules; j++) {
        NSDictionary *rule = [rulesArray objectAtIndex:j];
        NSArray *actions = [SmartSelectionController actionsInRule:rule];
        if (!actions.count) {
            DLog(@"Skipping rule with no actions:\n%@", rule);
            continue;
        }

        DLog(@"Evaluating rule:\n%@", rule);
        NSString *regex = [SmartSelectionController regexInRule:rule];
        for (int i = 0; i <= textWindow.length; i++) {
            NSString *substring = [textWindow substringWithRange:NSMakeRange(i, [textWindow length] - i)];
            NSError *regexError = nil;
            NSArray *components = [substring captureComponentsMatchedByRegex:regex
                                                                     options:0
                                                                       range:NSMakeRange(0, [substring length])
                                                                       error:&regexError];
            if (components.count) {
                DLog(@"Components for %@ are %@", regex, components);
                for (NSDictionary *action in actions) {
                    SEL mySelector = [self selectorForSmartSelectionAction:action];
                    NSString *theTitle =
                        [ContextMenuActionPrefsController titleForActionDict:action
                                                       withCaptureComponents:components
                                                            workingDirectory:[_dataSource workingDirectoryOnLine:line]
                                                                  remoteHost:[_dataSource remoteHostOnLine:line]];

                    NSMenuItem *theItem = [[[NSMenuItem alloc] initWithTitle:theTitle
                                                                      action:mySelector
                                                               keyEquivalent:@""] autorelease];
                    NSString *parameter =
                        [ContextMenuActionPrefsController parameterForActionDict:action
                                                           withCaptureComponents:components
                                                                workingDirectory:[_dataSource workingDirectoryOnLine:line]
                                                                      remoteHost:[_dataSource remoteHostOnLine:line]];
                    [theItem setRepresentedObject:parameter];
                    [theItem setTarget:self];
                    [theMenu addItem:theItem];
                    didAdd = YES;
                }
                break;
            }
        }
    }
    return didAdd;
}

- (void)contextMenuActionOpenFile:(id)sender
{
    DLog(@"Open file: '%@'", [sender representedObject]);
    [[NSWorkspace sharedWorkspace] openFile:[[sender representedObject] stringByExpandingTildeInPath]];
}

- (void)contextMenuActionOpenURL:(id)sender
{
    NSURL *url = [NSURL URLWithUserSuppliedString:[sender representedObject]];
    if (url) {
        DLog(@"Open URL: %@", [sender representedObject]);
        [[NSWorkspace sharedWorkspace] openURL:url];
    } else {
        DLog(@"%@ is not a URL", [sender representedObject]);
    }
}

- (void)contextMenuActionRunCommand:(id)sender {
    NSString *command = [sender representedObject];
    DLog(@"Run command: %@", command);
    [NSThread detachNewThreadSelector:@selector(runCommand:)
                             toTarget:[self class]
                           withObject:command];
}

- (void)contextMenuActionRunCommandInWindow:(id)sender {
    NSString *command = [sender representedObject];
    DLog(@"Run command in window: %@", command);
    [[iTermController sharedInstance] openSingleUseWindowWithCommand:command];
}

+ (void)runCommand:(NSString *)command
{

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    system([command UTF8String]);
    [pool drain];
}

- (void)contextMenuActionRunCoprocess:(id)sender
{
    NSString *command = [sender representedObject];
    DLog(@"Run coprocess: %@", command);
    [_delegate launchCoprocessWithCommand:command];
}

- (void)contextMenuActionSendText:(id)sender
{
    NSString *command = [sender representedObject];
    DLog(@"Send text: %@", command);
    [_delegate insertText:command];
}

// This method is called by control-click or by clicking the hamburger icon in the session title bar.
// Two-finger tap (or presumably right click with a mouse) would go through mouseUp->
// PointerController->openContextMenuWithEvent.
- (NSMenu *)menuForEvent:(NSEvent *)theEvent {
    if (theEvent) {
        // Control-click
        if ([iTermPreferences boolForKey:kPreferenceKeyControlLeftClickBypassesContextMenu]) {
            return nil;
        }
        NSMenu *menu = [self contextMenuWithEvent:theEvent];
        menu.delegate = self;
        return menu;
    } else {
        // Hamburger icon in session title view.
        NSMenu *menu = [self titleBarMenu];
        self.savedSelectedText = [self selectedText];
        menu.delegate = self;
        return menu;
    }
}

- (NSMenu *)titleBarMenu {
    return [self menuAtCoord:VT100GridCoordMake(-1, -1)];
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                                 toTopWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start = VT100GridCoordMake(0, 0);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                              toBottomWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    int maxY = MAX(0, [_dataSource numberOfLines] - 1);
    newRange.coordRange.start = VT100GridCoordMake(MAX(0, _dataSource.width - 1), maxY);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                         toStartOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = existingRange.columnWindow.location;
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                         toEndOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = [extractor lengthOfLine:newRange.coordRange.start.y];
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                  toStartOfIndentationWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start.x = [extractor startOfIndentationOnLine:existingRange.coordRange.start.y];
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                                    upWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.start.y = MAX(0, existingRange.coordRange.start.y - 1);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRange:(VT100GridWindowedRange)existingRange
                                  downWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    int maxY = [_dataSource numberOfLines];
    newRange.coordRange.start.y = MIN(maxY - 1, existingRange.coordRange.start.y + 1);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                               toTopWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end = VT100GridCoordMake(0, 0);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                            toBottomWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    int maxY = MAX(0, [_dataSource numberOfLines] - 1);
    newRange.coordRange.end = VT100GridCoordMake(MAX(0, _dataSource.width - 1), maxY);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                       toStartOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = existingRange.columnWindow.location;
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                         toEndOfLineWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = [extractor lengthOfLine:newRange.coordRange.end.y];
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                toStartOfIndentationWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end.x = [extractor startOfIndentationOnLine:existingRange.coordRange.end.y];
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                                  upWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    newRange.coordRange.end.y = MAX(0, existingRange.coordRange.end.y - 1);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingEndOfRange:(VT100GridWindowedRange)existingRange
                                downWithExtractor:(iTermTextExtractor *)extractor {
    VT100GridWindowedRange newRange = existingRange;
    int maxY = [_dataSource numberOfLines];
    newRange.coordRange.end.y = MIN(maxY - 1, existingRange.coordRange.end.y + 1);
    return newRange;
}

- (VT100GridWindowedRange)rangeByMovingStartOfRangeBack:(VT100GridWindowedRange)existingRange
                                              extractor:(iTermTextExtractor *)extractor
                                                   unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord coordBeforeStart =
        [extractor predecessorOfCoordSkippingContiguousNulls:VT100GridWindowedRangeStart(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridWindowedRange rangeWithCharacterBeforeStart = existingRange;
            rangeWithCharacterBeforeStart.coordRange.start = coordBeforeStart;
            return rangeWithCharacterBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridWindowedRange rangeWithWordBeforeStart =
                [extractor rangeForWordAt:coordBeforeStart maximumLength:kLongMaximumWordLength];
            rangeWithWordBeforeStart.coordRange.end = existingRange.coordRange.end;
            rangeWithWordBeforeStart.columnWindow = existingRange.columnWindow;
            return rangeWithWordBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridWindowedRange rangeWithLineBeforeStart = existingRange;
            if (rangeWithLineBeforeStart.coordRange.start.y > 0) {
                if (rangeWithLineBeforeStart.coordRange.start.x > rangeWithLineBeforeStart.columnWindow.location) {
                    rangeWithLineBeforeStart.coordRange.start.x = rangeWithLineBeforeStart.columnWindow.location;
                } else {
                    rangeWithLineBeforeStart.coordRange.start.y--;
                }
            }
            return rangeWithLineBeforeStart;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridWindowedRange rangeWithLineBeforeStart = existingRange;
            if (rangeWithLineBeforeStart.coordRange.start.y > 0) {
                int previousMark = [_dataSource lineNumberOfMarkBeforeLine:existingRange.coordRange.start.y];
                if (previousMark != -1) {
                    rangeWithLineBeforeStart.coordRange.start.y = previousMark + 1;
                    if (rangeWithLineBeforeStart.coordRange.start.y == existingRange.coordRange.start.y) {
                        previousMark = [_dataSource lineNumberOfMarkBeforeLine:existingRange.coordRange.start.y - 1];
                        if (previousMark != -1) {
                            rangeWithLineBeforeStart.coordRange.start.y = previousMark + 1;
                        }
                    }
                }
                rangeWithLineBeforeStart.coordRange.start.x = existingRange.columnWindow.location;
            }
            return rangeWithLineBeforeStart;
        }
    }
    assert(false);
}

- (VT100GridWindowedRange)rangeByMovingStartOfRangeForward:(VT100GridWindowedRange)existingRange
                                                 extractor:(iTermTextExtractor *)extractor
                                                      unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord coordAfterStart =
        [extractor successorOfCoordSkippingContiguousNulls:VT100GridWindowedRangeStart(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridWindowedRange rangeExcludingFirstCharacter = existingRange;
            rangeExcludingFirstCharacter.coordRange.start = coordAfterStart;
            return rangeExcludingFirstCharacter;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridCoord startCoord = VT100GridWindowedRangeStart(existingRange);
            BOOL startWasOnNull = [extractor characterAt:startCoord].code == 0;
            VT100GridWindowedRange rangeExcludingWordAtStart = existingRange;
            rangeExcludingWordAtStart.coordRange.start =
            [extractor rangeForWordAt:startCoord  maximumLength:kLongMaximumWordLength].coordRange.end;
            // If the start of range moved from a null to a null, skip to the end of the line or past all the nulls.
            if (startWasOnNull &&
                [extractor characterAt:rangeExcludingWordAtStart.coordRange.start].code == 0) {
                rangeExcludingWordAtStart.coordRange.start =
                [extractor successorOfCoordSkippingContiguousNulls:rangeExcludingWordAtStart.coordRange.start];
            }
            return rangeExcludingWordAtStart;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridWindowedRange rangeExcludingFirstLine = existingRange;
            rangeExcludingFirstLine.coordRange.start.x = existingRange.columnWindow.location;
            rangeExcludingFirstLine.coordRange.start.y =
            MIN(_dataSource.numberOfLines,
                rangeExcludingFirstLine.coordRange.start.y + 1);
            return rangeExcludingFirstLine;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridWindowedRange rangeExcludingFirstLine = existingRange;
            rangeExcludingFirstLine.coordRange.start.x = existingRange.columnWindow.location;
            int nextMark = [_dataSource lineNumberOfMarkAfterLine:rangeExcludingFirstLine.coordRange.start.y - 1];
            if (nextMark != -1) {
                rangeExcludingFirstLine.coordRange.start.y =
                    MIN(_dataSource.numberOfLines, nextMark + 1);
            }
            return rangeExcludingFirstLine;
        }
    }
    assert(false);
}

- (VT100GridWindowedRange)rangeByMovingEndOfRangeBack:(VT100GridWindowedRange)existingRange
                                            extractor:(iTermTextExtractor *)extractor
                                                 unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord coordBeforeEnd =
    [extractor predecessorOfCoordSkippingContiguousNulls:VT100GridWindowedRangeEnd(existingRange)];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridWindowedRange rangeExcludingLastCharacter = existingRange;
            rangeExcludingLastCharacter.coordRange.end = coordBeforeEnd;
            return rangeExcludingLastCharacter;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridWindowedRange rangeExcludingWordAtEnd = existingRange;
            rangeExcludingWordAtEnd.coordRange.end =
            [extractor rangeForWordAt:coordBeforeEnd maximumLength:kLongMaximumWordLength].coordRange.start;
            rangeExcludingWordAtEnd.columnWindow = existingRange.columnWindow;
            return rangeExcludingWordAtEnd;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridWindowedRange rangeExcludingLastLine = existingRange;
            if (existingRange.coordRange.end.x > existingRange.columnWindow.location) {
                rangeExcludingLastLine.coordRange.end.x = existingRange.columnWindow.location;
            } else {
                rangeExcludingLastLine.coordRange.end.x = existingRange.columnWindow.location;
                rangeExcludingLastLine.coordRange.end.y = MAX(1, existingRange.coordRange.end.y - 1);
            }
            return rangeExcludingLastLine;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridWindowedRange rangeExcludingLastLine = existingRange;
            int rightMargin;
            if (existingRange.columnWindow.length) {
                rightMargin = VT100GridRangeMax(existingRange.columnWindow) + 1;
            } else {
                rightMargin = _dataSource.width;
            }
            rangeExcludingLastLine.coordRange.end.x = rightMargin;
            int n = [_dataSource lineNumberOfMarkBeforeLine:rangeExcludingLastLine.coordRange.end.y + 1];
            if (n != -1) {
                rangeExcludingLastLine.coordRange.end.y = MAX(1, n - 1);
            }
            return rangeExcludingLastLine;
        }
    }
    assert(false);
}

- (VT100GridWindowedRange)rangeByMovingEndOfRangeForward:(VT100GridWindowedRange)existingRange
                                               extractor:(iTermTextExtractor *)extractor
                                                    unit:(PTYTextViewSelectionExtensionUnit)unit {
    VT100GridCoord endCoord = VT100GridWindowedRangeEnd(existingRange);
    VT100GridCoord coordAfterEnd =
        [extractor successorOfCoordSkippingContiguousNulls:endCoord];
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter: {
            VT100GridWindowedRange rangeWithCharacterAfterEnd = existingRange;
            rangeWithCharacterAfterEnd.coordRange.end = coordAfterEnd;
            return rangeWithCharacterAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitWord: {
            VT100GridWindowedRange rangeWithWordAfterEnd;
            if (endCoord.x > VT100GridRangeMax(existingRange.columnWindow)) {
                rangeWithWordAfterEnd = [extractor rangeForWordAt:coordAfterEnd maximumLength:kLongMaximumWordLength];
            } else {
                rangeWithWordAfterEnd = [extractor rangeForWordAt:endCoord maximumLength:kLongMaximumWordLength];
            }
            rangeWithWordAfterEnd.coordRange.start = existingRange.coordRange.start;
            rangeWithWordAfterEnd.columnWindow = existingRange.columnWindow;
            return rangeWithWordAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitLine: {
            VT100GridWindowedRange rangeWithLineAfterEnd = existingRange;
            int rightMargin;
            if (existingRange.columnWindow.length) {
                rightMargin = VT100GridRangeMax(existingRange.columnWindow) + 1;
            } else {
                rightMargin = _dataSource.width;
            }
            if (existingRange.coordRange.end.x < rightMargin) {
                rangeWithLineAfterEnd.coordRange.end.x = rightMargin;
            } else {
                rangeWithLineAfterEnd.coordRange.end.x = rightMargin;
                rangeWithLineAfterEnd.coordRange.end.y =
                MIN(_dataSource.numberOfLines,
                    rangeWithLineAfterEnd.coordRange.end.y + 1);
            }
            return rangeWithLineAfterEnd;
        }
        case kPTYTextViewSelectionExtensionUnitMark: {
            VT100GridWindowedRange rangeWithLineAfterEnd = existingRange;
            int rightMargin;
            if (existingRange.columnWindow.length) {
                rightMargin = VT100GridRangeMax(existingRange.columnWindow) + 1;
            } else {
                rightMargin = _dataSource.width;
            }
            rangeWithLineAfterEnd.coordRange.end.x = rightMargin;
            int nextMark =
                [_dataSource lineNumberOfMarkAfterLine:rangeWithLineAfterEnd.coordRange.end.y];
            if (nextMark != -1) {
                rangeWithLineAfterEnd.coordRange.end.y =
                    MIN(_dataSource.numberOfLines,
                        nextMark - 1);
            }
            if (rangeWithLineAfterEnd.coordRange.end.y == existingRange.coordRange.end.y) {
                int nextMark =
                    [_dataSource lineNumberOfMarkAfterLine:rangeWithLineAfterEnd.coordRange.end.y + 1];
                if (nextMark != -1) {
                    rangeWithLineAfterEnd.coordRange.end.y =
                        MIN(_dataSource.numberOfLines, nextMark - 1);
                }
            }
            return rangeWithLineAfterEnd;
        }
    }
    assert(false);
}

- (VT100GridWindowedRange)rangeByExtendingRange:(VT100GridWindowedRange)existingRange
                                       endpoint:(PTYTextViewSelectionEndpoint)endpoint
                                      direction:(PTYTextViewSelectionExtensionDirection)direction
                                      extractor:(iTermTextExtractor *)extractor
                                           unit:(PTYTextViewSelectionExtensionUnit)unit {
    switch (endpoint) {
        case kPTYTextViewSelectionEndpointStart:
            switch (direction) {
                case kPTYTextViewSelectionExtensionDirectionUp:
                    return [self rangeByMovingStartOfRange:existingRange
                                           upWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionLeft:
                    return [self rangeByMovingStartOfRangeBack:existingRange
                                                     extractor:extractor
                                                          unit:unit];

                case kPTYTextViewSelectionExtensionDirectionDown:
                    return [self rangeByMovingStartOfRange:existingRange
                                         downWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionRight:
                    return [self rangeByMovingStartOfRangeForward:existingRange
                                                        extractor:extractor
                                                             unit:unit];

                case kPTYTextViewSelectionExtensionDirectionStartOfLine:
                    return [self rangeByMovingStartOfRange:existingRange toStartOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionEndOfLine:
                    return [self rangeByMovingStartOfRange:existingRange toEndOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionTop:
                    return [self rangeByMovingStartOfRange:existingRange toTopWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionBottom:
                    return [self rangeByMovingStartOfRange:existingRange toBottomWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionStartOfIndentation:
                    return [self rangeByMovingStartOfRange:existingRange toStartOfIndentationWithExtractor:extractor];
            }
            assert(false);
            break;

        case kPTYTextViewSelectionEndpointEnd:
            switch (direction) {
                case kPTYTextViewSelectionExtensionDirectionUp:
                    return [self rangeByMovingEndOfRange:existingRange
                                         upWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionLeft:
                    return [self rangeByMovingEndOfRangeBack:existingRange
                                                   extractor:extractor
                                                        unit:unit];

                case kPTYTextViewSelectionExtensionDirectionDown:
                    return [self rangeByMovingEndOfRange:existingRange
                                       downWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionRight:
                    return [self rangeByMovingEndOfRangeForward:existingRange
                                                      extractor:extractor
                                                           unit:unit];

                case kPTYTextViewSelectionExtensionDirectionStartOfLine:
                    return [self rangeByMovingEndOfRange:existingRange toStartOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionEndOfLine:
                    return [self rangeByMovingEndOfRange:existingRange toEndOfLineWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionTop:
                    return [self rangeByMovingEndOfRange:existingRange toTopWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionBottom:
                    return [self rangeByMovingEndOfRange:existingRange toBottomWithExtractor:extractor];

                case kPTYTextViewSelectionExtensionDirectionStartOfIndentation:
                    return [self rangeByMovingEndOfRange:existingRange toStartOfIndentationWithExtractor:extractor];
            }
            assert(false);
            break;
    }
    assert(false);
}

- (iTermSelectionMode)selectionModeForExtensionUnit:(PTYTextViewSelectionExtensionUnit)unit {
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter:
            return kiTermSelectionModeCharacter;
        case kPTYTextViewSelectionExtensionUnitWord:
            return kiTermSelectionModeWord;
        case kPTYTextViewSelectionExtensionUnitLine:
            return kiTermSelectionModeLine;
        case kPTYTextViewSelectionExtensionUnitMark:
            return kiTermSelectionModeLine;
    }

    return kiTermSelectionModeCharacter;
}

- (BOOL)unitIsValid:(PTYTextViewSelectionExtensionUnit)unit {
    switch (unit) {
        case kPTYTextViewSelectionExtensionUnitCharacter:
        case kPTYTextViewSelectionExtensionUnitWord:
        case kPTYTextViewSelectionExtensionUnitLine:
        case kPTYTextViewSelectionExtensionUnitMark:
            return YES;
    }
    return NO;
}

- (VT100GridCoord)cursorCoord {
    return VT100GridCoordMake(_dataSource.cursorX - 1,
                              _dataSource.numberOfScrollbackLines + _dataSource.cursorY - 1);
}

- (void)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
                  inDirection:(PTYTextViewSelectionExtensionDirection)direction
                           by:(PTYTextViewSelectionExtensionUnit)unit {
    [self moveSelectionEndpoint:endpoint inDirection:direction by:unit cursorCoord:[self cursorCoord]];
}

- (void)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
                  inDirection:(PTYTextViewSelectionExtensionDirection)direction
                           by:(PTYTextViewSelectionExtensionUnit)unit
                  cursorCoord:(VT100GridCoord)cursorCoord {
    // Ensure the unit is valid, since it comes from preferences.
    if (![self unitIsValid:unit]) {
        XLog(@"ERROR: Unrecognized unit enumerated value %@, treating as character.", @(unit));
        unit = kPTYTextViewSelectionExtensionUnitCharacter;
    }

    // Cancel a live selection if one is ongoing.
    if (_selection.live) {
        [_selection endLiveSelection];
    }
    iTermSubSelection *sub = _selection.allSubSelections.lastObject;
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    VT100GridWindowedRange existingRange;
    // Create a selection at the cursor if none exists.
    if (!sub) {
        VT100GridCoord coord = cursorCoord;
        VT100GridRange columnWindow = extractor.logicalWindow;
        existingRange = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(coord.x, coord.y, coord.x, coord.y),
                                                   columnWindow.location,
                                                   columnWindow.length);
    } else {
        VT100GridRange columnWindow = sub.range.columnWindow;
        existingRange = sub.range;
        if (columnWindow.length > 0) {
            extractor.logicalWindow = columnWindow;
        }
    }


    VT100GridWindowedRange newRange = [self rangeByExtendingRange:existingRange
                                                         endpoint:endpoint
                                                        direction:direction
                                                        extractor:extractor
                                                             unit:unit];

    // Convert the mode into an iTermSelectionMode. Only a subset of iTermSelectionModes are
    // possible which is why this uses its own enum.
    iTermSelectionMode mode = [self selectionModeForExtensionUnit:unit];

    if (!sub) {
        [_selection beginSelectionAt:newRange.coordRange.start
                                mode:mode
                              resume:NO
                              append:NO];
        if (unit == kPTYTextViewSelectionExtensionUnitCharacter ||
            unit == kPTYTextViewSelectionExtensionUnitMark) {
            [_selection moveSelectionEndpointTo:newRange.coordRange.end];
        } else {
            [_selection moveSelectionEndpointTo:newRange.coordRange.start];
        }
        [_selection endLiveSelection];
    } else if ([_selection coord:newRange.coordRange.start isBeforeCoord:newRange.coordRange.end]) {
        // Is a valid range
        [_selection setLastRange:newRange mode:mode];
    } else {
        // Select a single character if the range is empty or flipped. This lets you move the
        // selection around like a cursor.
        switch (endpoint) {
            case kPTYTextViewSelectionEndpointStart:
                newRange.coordRange.end =
                    [extractor successorOfCoordSkippingContiguousNulls:newRange.coordRange.start];
                break;
            case kPTYTextViewSelectionEndpointEnd:
                newRange.coordRange.start =
                    [extractor predecessorOfCoordSkippingContiguousNulls:newRange.coordRange.end];
                break;
        }
        [_selection setLastRange:newRange mode:mode];
    }

    VT100GridCoordRange range = _selection.lastRange.coordRange;
    int start = range.start.y;
    int end = range.end.y;
    static const NSInteger kExtraLinesToMakeVisible = 2;
    switch (endpoint) {
        case kPTYTextViewSelectionEndpointStart:
            end = start;
            start = MAX(0, start - kExtraLinesToMakeVisible);
            break;

        case kPTYTextViewSelectionEndpointEnd:
            start = end;
            end += kExtraLinesToMakeVisible + 1;  // plus one because of the excess region
            break;
    }

    [self scrollLineNumberRangeIntoView:VT100GridRangeMake(start, end - start)];

    // Copy to pasteboard if needed.
    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (void)saveImageAs:(id)sender {
    iTermImageInfo *imageInfo = [sender representedObject];
    NSSavePanel* panel = [NSSavePanel savePanel];

    NSString *directory = [[NSFileManager defaultManager] downloadsDirectory] ?: NSHomeDirectory();
    [panel setDirectoryURL:[NSURL fileURLWithPath:directory] onceForID:@"saveImageAs"];
    panel.nameFieldStringValue = [imageInfo.filename lastPathComponent];
    panel.allowedFileTypes = @[ @"png", @"bmp", @"gif", @"jp2", @"jpeg", @"jpg", @"tiff" ];
    panel.allowsOtherFileTypes = NO;
    panel.canCreateDirectories = YES;
    [panel setExtensionHidden:NO];

    if ([panel runModal] == NSModalResponseOK) {
        NSString *filename = [[panel URL] path];
        [imageInfo saveToFile:filename];
    }
}

- (void)copyImage:(id)sender {
    iTermImageInfo *imageInfo = [sender representedObject];
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSPasteboardItem *item = imageInfo.pasteboardItem;
    if (item) {
        [pboard clearContents];
        [pboard writeObjects:@[ item ]];
    }
}

- (void)openImage:(id)sender {
    iTermImageInfo *imageInfo = [sender representedObject];
    NSString *name = imageInfo.nameForNewSavedTempFile;
    if (name) {
        [[iTermLaunchServices sharedInstance] openFile:name];
    }
}

- (void)inspectImage:(id)sender {
    iTermImageInfo *imageInfo = [sender representedObject];
    if (imageInfo) {
        NSString *text = [NSString stringWithFormat:
                          @"Filename: %@\n"
                          @"Dimensions: %d x %d",
                          imageInfo.filename,
                          (int)imageInfo.image.size.width,
                          (int)imageInfo.image.size.height];

        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = text;
        [alert addButtonWithTitle:@"OK"];
        [alert layout];
        [alert runModal];
    }
}

- (void)togglePauseAnimatingImage:(id)sender {
    iTermImageInfo *imageInfo = [sender representedObject];
    if (imageInfo) {
        imageInfo.paused = !imageInfo.paused;
        if (!imageInfo.paused) {
            // A redraw is needed to recompute which visible lines are animated
            // and ensure they keep getting redrawn on a fast cadence.
            [self setNeedsDisplay:YES];
        }
    }
}

- (iTermImageInfo *)imageInfoAtCoord:(VT100GridCoord)coord {
    if (coord.x < 0 ||
        coord.y < 0 ||
        coord.x >= [_dataSource width] ||
        coord.y >= [_dataSource numberOfLines]) {
        return nil;
    }
    screen_char_t* theLine = [_dataSource getLineAtIndex:coord.y];
    if (theLine && theLine[coord.x].image) {
        return GetImageInfo(theLine[coord.x].code);
    } else {
        return nil;
    }
}

- (void)reRunCommand:(id)sender
{
    NSString *command = [sender representedObject];
    [_delegate insertText:[command stringByAppendingString:@"\n"]];
}

- (void)selectCommandOutput:(id)sender {
    VT100ScreenMark *mark = [sender representedObject];
    VT100GridCoordRange range = [_dataSource textViewRangeOfOutputForCommandMark:mark];
    if (range.start.x == -1) {
        NSBeep();
        return;
    }
    [_selection beginSelectionAt:range.start
                            mode:kiTermSelectionModeCharacter
                          resume:NO
                          append:NO];
    [_selection moveSelectionEndpointTo:range.end];
    [_selection endLiveSelection];

    if ([iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText]) {
        [self copySelectionAccordingToUserPreferences];
    }
}

- (NSMenu *)menuForMark:(VT100ScreenMark *)mark directory:(NSString *)directory
{
    NSMenu *theMenu;

    // Allocate a menu
    theMenu = [[[NSMenu alloc] initWithTitle:@"Contextual Menu"] autorelease];

    NSMenuItem *theItem = [[[NSMenuItem alloc] init] autorelease];
    theItem.title = [NSString stringWithFormat:@"Command: %@", mark.command];
    [theMenu addItem:theItem];

    if (directory) {
        theItem = [[[NSMenuItem alloc] init] autorelease];
        theItem.title = [NSString stringWithFormat:@"Directory: %@", directory];
        [theMenu addItem:theItem];
    }

    theItem = [[[NSMenuItem alloc] init] autorelease];
    theItem.title = [NSString stringWithFormat:@"Return code: %d", mark.code];
    [theMenu addItem:theItem];

    if (mark.startDate) {
        theItem = [[[NSMenuItem alloc] init] autorelease];
        NSTimeInterval runningTime;
        if (mark.endDate) {
            runningTime = [mark.endDate timeIntervalSinceDate:mark.startDate];
        } else {
            runningTime = -[mark.startDate timeIntervalSinceNow];
        }
        int hours = runningTime / 3600;
        int minutes = ((int)runningTime % 3600) / 60;
        int seconds = (int)runningTime % 60;
        int millis = (int) ((runningTime - floor(runningTime)) * 1000);
        if (hours > 0) {
            theItem.title = [NSString stringWithFormat:@"Running time: %d:%02d:%02d",
                             hours, minutes, seconds];
        } else {
            theItem.title = [NSString stringWithFormat:@"Running time: %d:%02d.%03d",
                             minutes, seconds, millis];
        }
        [theMenu addItem:theItem];
    }

    [theMenu addItem:[NSMenuItem separatorItem]];

    theItem = [[[NSMenuItem alloc] initWithTitle:@"Re-run Command"
                                          action:@selector(reRunCommand:)
                                   keyEquivalent:@""] autorelease];
    [theItem setRepresentedObject:mark.command];
    [theMenu addItem:theItem];

    theItem = [[[NSMenuItem alloc] initWithTitle:@"Select Command Output"
                                          action:@selector(selectCommandOutput:)
                                   keyEquivalent:@""] autorelease];
    [theItem setRepresentedObject:mark];
    [theMenu addItem:theItem];

    return theMenu;
}

- (NSMenu *)menuAtCoord:(VT100GridCoord)coord {
    NSMenu *theMenu;

    // Allocate a menu
    theMenu = [[[NSMenu alloc] initWithTitle:@"Contextual Menu"] autorelease];
    iTermImageInfo *imageInfo = [self imageInfoAtCoord:coord];
    if (imageInfo) {
        // Show context menu for an image.
        NSArray *entryDicts;
        if (imageInfo.broken) {
            entryDicts =
                @[ @{ @"title": @"Save File As…",
                      @"selector": @"saveImageAs:" },
                   @{ @"title": @"Copy File",
                      @"selector": @"copyImage:" },
                   @{ @"title": @"Open File",
                      @"selector": @"openImage:" },
                   @{ @"title": @"Inspect",
                      @"selector": @"inspectImage:" } ];
        } else {
            entryDicts =
                @[ @{ @"title": @"Save Image As…",
                      @"selector": @"saveImageAs:" },
                   @{ @"title": @"Copy Image",
                      @"selector": @"copyImage:" },
                   @{ @"title": @"Open Image",
                      @"selector": @"openImage:" },
                   @{ @"title": @"Inspect",
                      @"selector": @"inspectImage:" } ];
        }
        if (imageInfo.animated || imageInfo.paused) {
            NSString *selector = @"togglePauseAnimatingImage:";
            if (imageInfo.paused) {
                entryDicts = [entryDicts arrayByAddingObject:@{ @"title": @"Resume Animating", @"selector": selector }];
            } else {
                entryDicts = [entryDicts arrayByAddingObject:@{ @"title": @"Stop Animating", @"selector": selector }];
            }
        }
        for (NSDictionary *entryDict in entryDicts) {
            NSMenuItem *item;

            item = [[[NSMenuItem alloc] initWithTitle:entryDict[@"title"]
                                               action:NSSelectorFromString(entryDict[@"selector"])
                                        keyEquivalent:@""] autorelease];
            [item setRepresentedObject:imageInfo];
            [theMenu addItem:item];
        }
        return theMenu;
    }

    if ([self _haveShortSelection]) {
        NSString *text = [self selectedText];
        NSArray<NSString *> *synonyms = [text helpfulSynonyms];
        for (NSString *conversion in synonyms) {
            NSMenuItem *theItem = [[[NSMenuItem alloc] init] autorelease];
            theItem.title = conversion;
            [theMenu addItem:theItem];
        }
        if (synonyms.count) {
            [theMenu addItem:[NSMenuItem separatorItem]];
        }
    }

    // Menu items for acting on text selections
    NSString *scpTitle = @"Download with scp";
    if ([self _haveShortSelection]) {
        SCPPath *scpPath = [_dataSource scpPathForFile:[self selectedText]
                                                onLine:_selection.lastRange.coordRange.start.y];
        if (scpPath) {
            scpTitle = [NSString stringWithFormat:@"Download with scp from %@", scpPath.hostname];
        }
    }

    [theMenu addItemWithTitle:scpTitle
                       action:@selector(downloadWithSCP:)
                keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Open Selection as URL"
                     action:@selector(browse:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];
    [theMenu addItemWithTitle:@"Search the Web for Selection"
                     action:@selector(searchInBrowser:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];
    [theMenu addItemWithTitle:@"Send Email to Selected Address"
                     action:@selector(mail:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Custom actions
    if ([_selection hasSelection] &&
        [_selection length] < kMaxSelectedTextLengthForCustomActions) {
        NSString *selectedText = [self selectedTextCappedAtSize:1024];
        if ([self addCustomActionsToMenu:theMenu matchingText:selectedText line:coord.y]) {
            [theMenu addItem:[NSMenuItem separatorItem]];
        }
    }

    // Split pane options
    [theMenu addItemWithTitle:@"Split Pane Vertically" action:@selector(splitTextViewVertically:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    [theMenu addItemWithTitle:@"Split Pane Horizontally" action:@selector(splitTextViewHorizontally:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    [theMenu addItemWithTitle:@"Move Session to Split Pane" action:@selector(movePane:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    [theMenu addItemWithTitle:@"Move Session to Window" action:@selector(moveSessionToWindow:) keyEquivalent:@""];

    [theMenu addItemWithTitle:@"Swap With Session…" action:@selector(swapSessions:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Copy,  paste, and save
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Copy",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(copy:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Paste",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(paste:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Save",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(saveDocumentAs:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Select all
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Select All",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(selectAll:) keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Clear buffer
    [theMenu addItemWithTitle:@"Clear Buffer"
                       action:@selector(clearTextViewBuffer:)
                keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Make note
    [theMenu addItemWithTitle:@"Annotate Selection"
                       action:@selector(addNote:)
                keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    [theMenu addItemWithTitle:@"Show Note"
                       action:@selector(showNotes:)
                keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Edit Session
    [theMenu addItemWithTitle:@"Edit Session..."
                       action:@selector(editTextViewSession:)
                keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Toggle broadcast
    [theMenu addItemWithTitle:@"Toggle Broadcasting Input"
                       action:@selector(toggleBroadcastingInput:)
                keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Close current pane
    [theMenu addItemWithTitle:@"Close"
                       action:@selector(closeTextViewSession:)
                keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Restart"
                       action:@selector(restartTextViewSession:)
                keyEquivalent:@""];
    [[theMenu itemAtIndex:[theMenu numberOfItems] - 1] setTarget:self];

    // Ask the delegate if there is anything to be added
    if ([[self delegate] respondsToSelector:@selector(menuForEvent:menu:)]) {
        [[self delegate] menuForEvent:nil menu:theMenu];
    }

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];
    [theMenu addItemWithTitle:@"Bury"
                       action:@selector(bury:)
                keyEquivalent:@""];

    return theMenu;
}

- (IBAction)bury:(id)sender {
    [_delegate textViewBurySession];
}

- (void)mail:(id)sender
{
    NSString* mailto;

    if ([[self selectedText] hasPrefix:@"mailto:"]) {
        mailto = [NSString stringWithString:[self selectedText]];
    } else {
        mailto = [NSString stringWithFormat:@"mailto:%@", [self selectedText]];
    }

    NSString *escapedString = [mailto stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"!*'();:@&=+$,/?%#[]"]];

    NSURL* url = [NSURL URLWithString:escapedString];

    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)browse:(id)sender {
    [self findUrlInString:[self selectedText] andOpenInBackground:NO];
}

- (void)searchInBrowser:(id)sender
{
    NSString* url =
        [NSString stringWithFormat:[iTermAdvancedSettingsModel searchCommand],
                                   [[self selectedText] stringWithPercentEscape]];
    [self findUrlInString:url andOpenInBackground:NO];
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
    }
    NSDragOperation operation = [self dragOperationForSender:sender numberOfValidItems:&numValid];
    if (numValid != sender.numberOfValidItemsForDrop) {
        sender.numberOfValidItemsForDrop = numValid;
    }
    [self setNeedsDisplay:YES];
    return operation;
}

- (void)draggingExited:(nullable id <NSDraggingInfo>)sender {
    _drawingHelper.showDropTargets = NO;
    [self setNeedsDisplay:YES];
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
        [self setNeedsDisplay:YES];
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

- (BOOL)confirmUploadOfFiles:(NSArray *)files toPath:(SCPPath *)path {
    NSString *text;
    if (files.count == 0) {
        return NO;
    }
    if (files.count == 1) {
        text = [NSString stringWithFormat:@"Ok to scp\n%@\nto\n%@@%@:%@?",
                [files componentsJoinedByString:@", "],
                path.username, path.hostname, path.path];
    } else {
        text = [NSString stringWithFormat:@"Ok to scp the following files:\n%@\n\nto\n%@@%@:%@?",
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
    NSArray *filenames = [pasteboard filenamesOnPasteboardWithShellEscaping:NO];
    if ([types containsObject:NSFilenamesPboardType] && filenames.count && dropScpPath) {
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

- (BOOL)pasteValuesOnPasteboard:(NSPasteboard *)pasteboard cdToDirectory:(BOOL)cdToDirectory {
    // Paste string or filenames in.
    NSArray *types = [pasteboard types];

    if ([types containsObject:NSFilenamesPboardType]) {
        // Filenames were dragged.
        NSArray *filenames = [pasteboard filenamesOnPasteboardWithShellEscaping:YES];
        if (filenames.count) {
            BOOL pasteNewline = NO;

            if (cdToDirectory) {
                // cmd-drag: "cd" to dragged directory (well, we assume it's a directory).
                // If multiple files are dragged, balk.
                if (filenames.count > 1) {
                    return NO;
                } else {
                    [_delegate pasteString:@"cd "];
                    pasteNewline = YES;
                }
            }

            // Paste filenames separated by spaces.
            [_delegate pasteString:[filenames componentsJoinedByString:@" "]];

            if (pasteNewline) {
                // For cmd-drag, we append a newline.
                [_delegate pasteString:@"\r"];
            } else if (!cdToDirectory) {
                [_delegate pasteString:@" "];
            }
            return YES;
        }
    }

    if ([types containsObject:NSStringPboardType]) {
        NSString *string = [pasteboard stringForType:NSStringPboardType];
        if (string.length) {
            [_delegate pasteString:string];
            return YES;
        }
    }

    return NO;
}

//
// Called when the dragged item is released in our drop area.
//
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    _drawingHelper.showDropTargets = NO;
    NSPasteboard *draggingPasteboard = [sender draggingPasteboard];
    NSDragOperation dragOperation = [sender draggingSourceOperationMask];
    DLog(@"Perform drag operation");
    if (dragOperation & (NSDragOperationCopy | NSDragOperationGeneric)) {
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

// Save method
- (void)saveDocumentAs:(id)sender {
    // We get our content of the textview or selection, if any
    NSString *aString = [self selectedText];
    if (!aString) {
        aString = [self content];
    }

    NSData *aData = [aString dataUsingEncoding:[_delegate textViewEncoding]
                          allowLossyConversion:YES];

    // initialize a save panel
    NSSavePanel *aSavePanel = [NSSavePanel savePanel];
    [aSavePanel setAccessoryView:nil];

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
    [aSavePanel setDirectoryURL:[NSURL fileURLWithPath:path] onceForID:@"saveDocumentAs:"];
    aSavePanel.nameFieldStringValue = nowStr;
    if ([aSavePanel runModal] == NSFileHandlingPanelOKButton) {
        if (![aData writeToFile:aSavePanel.URL.path atomically:YES]) {
            NSBeep();
        }
    }
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
                                       attributeProvider:^NSDictionary *(screen_char_t theChar) {
                                           return [self charAttributes:theChar];
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
    [printInfo setHorizontalPagination:NSFitPagination];
    [printInfo setVerticalPagination:NSAutoPagination];
    [printInfo setVerticallyCentered:NO];

    // Create a temporary view with the contents, change to black on white, and
    // print it.
    NSRect frame = [[self enclosingScrollView] documentVisibleRect];
    NSTextView *tempView =
        [[[NSTextView alloc] initWithFrame:frame] autorelease];

    iTermPrintAccessoryViewController *accessory = nil;
    NSAttributedString *attributedString;
    NSDictionary *attributes =
        @{ NSBackgroundColorAttributeName: [NSColor textBackgroundColor],
           NSForegroundColorAttributeName: [NSColor textColor],
           NSFontAttributeName: [NSFont userFixedPitchFontOfSize:0] };
    if ([content isKindOfClass:[NSAttributedString class]]) {
        attributedString = content;
        accessory = [[[iTermPrintAccessoryViewController alloc] initWithNibName:@"iTermPrintAccessoryViewController"
                                                                         bundle:[NSBundle bundleForClass:self.class]] autorelease];
        accessory.userDidChangeSetting = ^() {
            NSAttributedString *theAttributedString = nil;
            if (accessory.blackAndWhite) {
                theAttributedString = [[[NSAttributedString alloc] initWithString:[content string]
                                                                       attributes:attributes] autorelease];
            } else {
                theAttributedString = attributedString;
            }
            [[tempView textStorage] setAttributedString:theAttributedString];
        };
    } else {
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

- (void)doCommandBySelector:(SEL)aSelector
{
    DLog(@"doCommandBySelector:%@", NSStringFromSelector(aSelector));
    if (gCurrentKeyEventTextView && self != gCurrentKeyEventTextView) {
        // See comment in -keyDown:
        DLog(@"Rerouting doCommandBySelector from %@ to %@", self, gCurrentKeyEventTextView);
        [gCurrentKeyEventTextView doCommandBySelector:aSelector];
        return;
    }

    if ([iTermAdvancedSettingsModel experimentalKeyHandling]) {
        // Pass the event to the delegate since doCommandBySelector was called instead of
        // insertText:replacementRange:, unless an IME is in use. An example of when this gets called
        // but we should not pass the event to the delegate is when there is marked text and you press
        // Enter.
        if (![self hasMarkedText] && !_hadMarkedTextBeforeHandlingKeypressEvent && _eventBeingHandled) {
            _keyPressHandled = YES;
            [self.delegate keyDown:_eventBeingHandled];
        }
    }
    DLog(@"doCommandBySelector:%@", NSStringFromSelector(aSelector));
}

// TODO: Respect replacementRange
- (void)insertText:(id)aString replacementRange:(NSRange)replacementRange {
    DLog(@"insertText:%@ replacementRange:%@", aString ,NSStringFromRange(replacementRange));
    if ([aString isKindOfClass:[NSAttributedString class]]) {
        aString = [aString string];
    }
    if (gCurrentKeyEventTextView && self != gCurrentKeyEventTextView) {
        // See comment in -keyDown:
        DLog(@"Rerouting insertText from %@ to %@", self, gCurrentKeyEventTextView);
        [gCurrentKeyEventTextView insertText:aString];
        return;
    }

    // See issue 6699
    aString = [aString stringByReplacingOccurrencesOfString:@"¥" withString:@"\\"];

    DLog(@"PTYTextView insertText:%@", aString);
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

        _keyPressHandled = YES;
    }

    if ([self hasMarkedText]) {
        // In case imeOffset changed, the frame height must adjust.
        [_delegate refresh];
    }
}

// Legacy NSTextInput method, probably not used by the system but used internally.
- (void)insertText:(id)aString {
    // TODO: The replacement range is wrong
    [self insertText:aString replacementRange:NSMakeRange(0, [_drawingHelper.markedText length])];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    _firstMouseEventNumber = [theEvent eventNumber];
    return YES;
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
    return _drawingHelper.inputMethodMarkedRange.length > 0;
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
    DLog(@"selectedRange->NSNotFound");
    return NSMakeRange(NSNotFound, 0);
}

- (NSArray *)validAttributesForMarkedText
{
    return @[ NSForegroundColorAttributeName,
              NSBackgroundColorAttributeName,
              NSUnderlineStyleAttributeName,
              NSFontAttributeName ];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange
{
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

    NSRect rect=NSMakeRect(x * _charWidth + [iTermAdvancedSettingsModel terminalMargin],
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

- (BOOL)findInProgress {
    return _findOnPageHelper.findInProgress;
}

- (void)setSemanticHistoryPrefs:(NSDictionary *)prefs {
    self.semanticHistoryController.prefs = prefs;
}

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
        _drawingHelper.badgeImage = _badgeLabel.image;
        [self setNeedsDisplay:YES];
    }
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

#pragma mark - Find on page

- (void)addSearchResult:(SearchResult *)searchResult {
    [_findOnPageHelper addSearchResult:searchResult width:[_dataSource width]];
}

- (FindContext *)findContext {
    return _findOnPageHelper.copiedContext;
}

- (BOOL)continueFind:(double *)progress {
    return [_findOnPageHelper continueFind:progress
                                   context:[_dataSource findContext]
                                     width:[_dataSource width]
                             numberOfLines:[_dataSource numberOfLines]
                        overflowAdjustment:[_dataSource totalScrollbackOverflow] - [_dataSource scrollbackOverflow]];
}

- (BOOL)continueFindAllResults:(NSMutableArray *)results inContext:(FindContext *)context {
    return [_dataSource continueFindAllResults:results inContext:context];
}

- (void)findOnPageSetFindString:(NSString*)aString
               forwardDirection:(BOOL)direction
                           mode:(iTermFindMode)mode
                    startingAtX:(int)x
                    startingAtY:(int)y
                     withOffset:(int)offset
                      inContext:(FindContext*)context
                multipleResults:(BOOL)multipleResults {
    [_dataSource setFindString:aString
              forwardDirection:direction
                          mode:mode
                   startingAtX:x
                   startingAtY:y
                    withOffset:offset
                     inContext:context
               multipleResults:multipleResults];
}

- (void)findOnPageSelectRange:(VT100GridCoordRange)range wrapped:(BOOL)wrapped {
    [_selection clearSelection];
    iTermSubSelection *sub =
        [iTermSubSelection subSelectionWithRange:VT100GridWindowedRangeMake(range, 0, 0)
                                            mode:kiTermSelectionModeCharacter];
    [_selection addSubSelection:sub];
    if (!wrapped) {
        [self setNeedsDisplay:YES];
    }
    [_delegate textViewDidSelectRangeForFindOnPage:range];
}

- (void)findOnPageSaveFindContextAbsPos {
    [_dataSource saveFindContextAbsPos];
}

- (void)findOnPageDidWrapForwards:(BOOL)directionIsForwards {
    if (directionIsForwards) {
        [self beginFlash:kiTermIndicatorWrapToTop];
    } else {
        [self beginFlash:kiTermIndicatorWrapToBottom];
    }
}

- (void)findOnPageRevealRange:(VT100GridCoordRange)range {
    // Lock scrolling after finding text
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];

    [self _scrollToCenterLine:range.end.y];
    [self setNeedsDisplay:YES];
}

- (void)findOnPageFailed {
    [_selection clearSelection];
    [self setNeedsDisplay:YES];
}

- (void)resetFindCursor {
    [_findOnPageHelper resetFindCursor];
}

- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset {
    [_findOnPageHelper findString:aString
                 forwardDirection:direction
                             mode:mode
                       withOffset:offset
                          context:[_dataSource findContext]
                    numberOfLines:[_dataSource numberOfLines]
          totalScrollbackOverflow:[_dataSource totalScrollbackOverflow]];
}

- (void)clearHighlights:(BOOL)resetContext {
    [_findOnPageHelper clearHighlights];
    if (resetContext) {
        [_findOnPageHelper resetCopiedFindContext];
    } else {
        [_findOnPageHelper removeAllSearchResults];
    }
}

- (void)setTransparency:(double)fVal {
    _transparency = fVal;
    [self setNeedsDisplay:YES];
    [_delegate textViewBackgroundColorDidChange];
}

- (void)setTransparencyAffectsOnlyDefaultBackgroundColor:(BOOL)value {
    _drawingHelper.transparencyAffectsOnlyDefaultBackgroundColor = value;
    [self setNeedsDisplay:YES];
}

- (float)blend {
    return _drawingHelper.blend;
}

- (void)setBlend:(float)fVal {
    _drawingHelper.blend = MIN(MAX(0.05, fVal), 1);
    [self setNeedsDisplay:YES];
}

- (void)setUseSmartCursorColor:(BOOL)value {
    _drawingHelper.useSmartCursorColor = value;
}

- (BOOL)useSmartCursorColor {
    return _drawingHelper.useSmartCursorColor;
}

- (void)setMinimumContrast:(double)value {
    _drawingHelper.minimumContrast = value;
    [_colorMap setMinimumContrast:value];
}

- (BOOL)useTransparency {
    return [_delegate textViewWindowUsesTransparency];
}

// service stuff
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
    NSSet *acceptedReturnTypes = [NSSet setWithArray:@[ (NSString *)kUTTypeUTF8PlainText,
                                                        NSStringPboardType ]];
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

// Service
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types {
    // It is agonizingly slow to copy hundreds of thousands of lines just because the context
    // menu is opening. Services use this to get access to the clipboard contents but
    // it's lousy to hang for a few minutes for a feature that won't be used very much, esp. for
    // such large selections. In OS 10.9 this is called when opening the context menu, even though
    // it is deprecated by 10.9.
    NSString *copyString =
        [self selectedTextCappedAtSize:[iTermAdvancedSettingsModel maximumBytesToProvideToServices]];

    if (copyString && [copyString length] > 0) {
        [pboard declareTypes:@[ NSStringPboardType ] owner:self];
        [pboard setString:copyString forType:NSStringPboardType];
        return YES;
    }

    return NO;
}

// Service
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard {
    NSString *string = [pboard stringForType:NSStringPboardType];
    if (string.length) {
        [_delegate insertText:string];
        return YES;
    } else {
        return NO;
    }
}

// This textview is about to be hidden behind another tab.
- (void)aboutToHide {
    [_selectionScrollHelper mouseUp];
}

- (void)beginFlash:(NSString *)flashIdentifier {
    if ([flashIdentifier isEqualToString:kiTermIndicatorBell] &&
        [iTermAdvancedSettingsModel traditionalVisualBell]) {
        [_indicatorsHelper beginFlashingFullScreen];
    } else {
        [_indicatorsHelper beginFlashingIndicator:flashIdentifier];
    }
}

- (void)highlightMarkOnLine:(int)line hasErrorCode:(BOOL)hasErrorCode {
    CGFloat y = line * _lineHeight;
    NSView *highlightingView = [[[NSView alloc] initWithFrame:NSMakeRect(0, y, self.frame.size.width, _lineHeight)] autorelease];
    [highlightingView setWantsLayer:YES];
    [self addSubview:highlightingView];

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
    const NSTimeInterval duration = 0.75;

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
    [_delegate textViewDidHighightMark];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self removeHighlightedRow:entry];
        [entry release];
    });
}

- (void)removeHighlightedRow:(iTermHighlightedRow *)row {
    [_highlightedRows removeObject:row];
}

#pragma mark - Find Cursor

- (NSRect)cursorFrame {
    int lineStart = [_dataSource numberOfLines] - [_dataSource height];
    int cursorX = [_dataSource cursorX] - 1;
    int cursorY = [_dataSource cursorY] - 1;
    return NSMakeRect([iTermAdvancedSettingsModel terminalMargin] + cursorX * _charWidth,
                      (lineStart + cursorY) * _lineHeight,
                      _charWidth,
                      _lineHeight);
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
    _drawingHelper.cursorVisible = YES;
    [self setNeedsDisplayInRect:self.cursorFrame];
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

- (BOOL)getAndResetChangedSinceLastExpose
{
    BOOL temp = _changedSinceLastExpose;
    _changedSinceLastExpose = NO;
    return temp;
}

- (BOOL)isAnyCharSelected
{
    return [_selection hasSelection];
}

- (NSString *)getWordForX:(int)x
                        y:(int)y
                    range:(VT100GridWindowedRange *)rangePtr
          respectDividers:(BOOL)respectDividers {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
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

#pragma mark - Semantic History Delegate

- (void)semanticHistoryLaunchCoprocessWithCommand:(NSString *)command {
    [_delegate launchCoprocessWithCommand:command];
}

- (PTYFontInfo *)getFontForChar:(UniChar)ch
                      isComplex:(BOOL)isComplex
                     renderBold:(BOOL *)renderBold
                   renderItalic:(BOOL *)renderItalic {
    return [PTYFontInfo fontForAsciiCharacter:(!isComplex && (ch < 128))
                                    asciiFont:_primaryFont
                                 nonAsciiFont:_secondaryFont
                                  useBoldFont:_useBoldFont
                                useItalicFont:_useItalicFont
                             usesNonAsciiFont:_useNonAsciiFont
                                   renderBold:renderBold
                                 renderItalic:renderItalic];
}

#pragma mark - Private methods

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
                        [_delegate textViewUnicodeVersion]);

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
        if (curX == 0 && buf[i].code == DWC_RIGHT) {
            ++extra;
            ++curX;
        }
        ++curX;
        curX %= width;
    }
    return len + extra;
}

- (double)transparencyAlpha {
    return [self useTransparency] ? 1.0 - _transparency : 1.0;
}

- (void)useBackgroundIndicatorChanged:(NSNotification *)notification {
    _showStripesWhenBroadcastingInput = [iTermApplication.sharedApplication delegate].useBackgroundPatternIndicator;
    [self setNeedsDisplay:YES];
}

- (void)_scrollToLine:(int)line
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = line * _lineHeight;
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = _lineHeight;
    [self scrollRectToVisible:aFrame];
}

- (void)_scrollToCenterLine:(int)line {
    NSRect visible = [self visibleRect];
    int visibleLines = (visible.size.height - [iTermAdvancedSettingsModel terminalVMargin] * 2) / _lineHeight;
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

- (NSRect)visibleContentRect {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    visibleRect.size.height -= [self excess];
    visibleRect.size.height -= [iTermAdvancedSettingsModel terminalVMargin];
    return visibleRect;
}

- (void)scrollBottomOfRectToBottomOfVisibleArea:(NSRect)rect {
    NSPoint p = rect.origin;
    p.y += rect.size.height;
    NSRect visibleRect = [self visibleContentRect];
    p.y -= visibleRect.size.height;
    p.y = MAX(0, p.y);
    [[[self enclosingScrollView] contentView] scrollToPoint:p];
}

- (VT100GridRange)rangeOfVisibleLines {
    NSRect visibleRect = [self visibleContentRect];
    int start = [self coordForPoint:visibleRect.origin allowRightMarginOverflow:NO].y;
    int end = [self coordForPoint:NSMakePoint(0, NSMaxY(visibleRect) - 1) allowRightMarginOverflow:NO].y;
    return VT100GridRangeMake(start, MAX(0, end - start));
}

- (void)scrollLineNumberRangeIntoView:(VT100GridRange)range {
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    int firstVisibleLine = visibleRect.origin.y / _lineHeight;
    int lastVisibleLine = firstVisibleLine + [_dataSource height];
    if (range.location >= firstVisibleLine && range.location + range.length <= lastVisibleLine) {
      // Already visible
      return;
    }
    if (range.length < [_dataSource height]) {
        [self _scrollToCenterLine:range.location + range.length / 2];
    } else {
        NSRect aFrame;
        aFrame.origin.x = 0;
        aFrame.origin.y = range.location * _lineHeight;
        aFrame.size.width = [self frame].size.width;
        aFrame.size.height = range.length * _lineHeight;

        [self scrollBottomOfRectToBottomOfVisibleArea:aFrame];
    }
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

- (BOOL)_haveHardNewlineAtY:(int)y
{
    screen_char_t *theLine;
    theLine = [_dataSource getLineAtIndex:y];
    const int w = [_dataSource width];
    return !theLine[w].complexChar && theLine[w].code == EOL_HARD;
}

- (NSString*)_getCharacterAtX:(int)x Y:(int)y
{
    screen_char_t *theLine;
    theLine = [_dataSource getLineAtIndex:y];

    if (theLine[x].complexChar) {
        return ComplexCharToStr(theLine[x].code);
    } else {
        return [NSString stringWithCharacters:&theLine[x].code length:1];
    }
}

- (PTYCharType)classifyChar:(unichar)ch
                  isComplex:(BOOL)isComplex
{
    NSString* aString = CharToStr(ch, isComplex);
    UTF32Char longChar = CharToLongChar(ch, isComplex);

    if (longChar == DWC_RIGHT || longChar == DWC_SKIP) {
        return CHARTYPE_DW_FILLER;
    } else if (!longChar ||
               [[NSCharacterSet whitespaceCharacterSet] longCharacterIsMember:longChar] ||
               ch == TAB_FILLER) {
        return CHARTYPE_WHITESPACE;
    } else if ([[NSCharacterSet alphanumericCharacterSet] longCharacterIsMember:longChar] ||
               [[iTermPreferences stringForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection] rangeOfString:aString].length != 0) {
        return CHARTYPE_WORDCHAR;
    } else {
        // Non-alphanumeric, non-whitespace, non-word, not double-width filler.
        // Miscellaneous symbols, etc.
        return CHARTYPE_OTHER;
    }
}

- (BOOL)shouldSelectCharForWord:(unichar)ch
                      isComplex:(BOOL)isComplex
                selectWordChars:(BOOL)selectWordChars
{
    switch ([self classifyChar:ch isComplex:isComplex]) {
        case CHARTYPE_WHITESPACE:
            return !selectWordChars;
            break;

        case CHARTYPE_WORDCHAR:
        case CHARTYPE_DW_FILLER:
            return selectWordChars;
            break;

        case CHARTYPE_OTHER:
            return NO;
            break;
    };
    return NO;
}

// Any sequence of words separated by spaces or tabs could be a filename. Search the neighborhood
// of words for a valid filename. For example, beforeString could be "blah blah ~/Library/Appli" and
// afterString could be "cation Support/Screen Sharing foo bar baz". This searches outward from
// the point between beforeString and afterString to find a valid path, and would return
// "~/Library/Application Support/Screen sharing" if such a file exists.

// Find the bounding rectangle of what could possibly be a single semantic
// string with a character at xi,yi. Lines of | characters are treated as a
// vertical bound.
- (NSRect)boundingRectForCharAtX:(int)xi y:(int)yi
{
    int w = [_dataSource width];
    int h = [_dataSource numberOfLines];
    int minX = 0;
    int maxX = w - 1;

    // Find lines of at least two | characters on either side of xi,yi to define the min and max
    // horizontal bounds.
    for (int i = xi; i >= 0; i--) {
        if ([[self _getCharacterAtX:i Y:yi] isEqualToString:@"|"] &&
            ((yi > 0 && [[self _getCharacterAtX:i Y:yi - 1] isEqualToString:@"|"]) ||
             (yi < h - 1 && [[self _getCharacterAtX:i Y:yi + 1] isEqualToString:@"|"]))) {
            minX = i + 1;
            break;
        }
    }
    for (int i = xi; i < w; i++) {
        if ([[self _getCharacterAtX:i Y:yi] isEqualToString:@"|"] &&
            ((yi > 0 && [[self _getCharacterAtX:i Y:yi - 1] isEqualToString:@"|"]) ||
             (yi < h - 1 && [[self _getCharacterAtX:i Y:yi + 1] isEqualToString:@"|"]))) {
            maxX = i - 1;
            break;
        }
    }

    // We limit the esarch to 10 lines in each direction.
    // See how high the lines of pipes go
    int minY = MAX(0, yi - 10);
    int maxY = MIN(h - 1, yi + 10);
    for (int i = yi; i >= yi - 10 && i >= 0; i--) {
        if (minX != 0) {
            if (![[self _getCharacterAtX:minX - 1 Y:i] isEqualToString:@"|"]) {
                minY = i + 1;
                break;
            }
        }
        if (maxX != w - 1) {
            if (![[self _getCharacterAtX:maxX + 1 Y:i] isEqualToString:@"|"]) {
                minY = i + 1;
                break;
            }
        }
    }

    // See how low the lines of pipes go
    for (int i = yi; i < h && i < yi + 10; i++) {
        if (minX != 0) {
            if (![[self _getCharacterAtX:minX - 1 Y:i] isEqualToString:@"|"]) {
                maxY = i - 1;
                break;
            }
        }
        if (maxX != w - 1) {
            if (![[self _getCharacterAtX:maxX + 1 Y:i] isEqualToString:@"|"]) {
                maxY = i - 1;
                break;
            }
        }
    }

    return NSMakeRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}


- (URLAction *)urlActionForClickAtX:(int)x
                                  y:(int)y
             respectingHardNewlines:(BOOL)respectHardNewlines {
    DLog(@"urlActionForClickAt:%@,%@ respectingHardNewlines:%@",
         @(x), @(y), @(respectHardNewlines));
    if (y < 0) {
        return nil;
    }
    const VT100GridCoord coord = VT100GridCoordMake(x, y);
    iTermImageInfo *imageInfo = [self imageInfoAtCoord:coord];
    if (imageInfo) {
        return [URLAction urlActionToOpenImage:imageInfo];
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    if ([extractor characterAt:coord].code == 0) {
        return nil;
    }
    [extractor restrictToLogicalWindowIncludingCoord:coord];

    NSString *workingDirectory = [_dataSource workingDirectoryOnLine:y];
    DLog(@"According to data source, the working directory on line %d is %@", y, workingDirectory);
    if (!workingDirectory) {
        // Well, just try the current directory then.
        DLog(@"That failed, so try to get the current working directory...");
        workingDirectory = [_delegate textViewCurrentWorkingDirectory];
        DLog(@"It is %@", workingDirectory);
    }

    return [iTermURLActionFactory urlActionAtCoord:VT100GridCoordMake(x, y)
                               respectHardNewlines:respectHardNewlines
                                  workingDirectory:workingDirectory ?: @""
                                        remoteHost:[_dataSource remoteHostOnLine:y]
                                         selectors:[self smartSelectionActionSelectorDictionary]
                                             rules:_smartSelectionRules
                                         extractor:extractor
                         semanticHistoryController:self.semanticHistoryController
                                       pathFactory:^SCPPath *(NSString *path, int line) {
                                           return [_dataSource scpPathForFile:path onLine:line];
                                       }];
}

- (void)imageDidLoad:(NSNotification *)notification {
    if ([self missingImageIsVisible:notification.object]) {
        [self setNeedsDisplay:YES];
    }
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    [self refuseFirstResponderAtCurrentMouseLocation];
}

- (BOOL)missingImageIsVisible:(iTermImageInfo *)image {
    if (![_drawingHelper.missingImages containsObject:image.uniqueIdentifier]) {
        return NO;
    }
    return [self imageIsVisible:image];
}

- (BOOL)imageIsVisible:(iTermImageInfo *)image {
    int firstVisibleLine = [[self enclosingScrollView] documentVisibleRect].origin.y / _lineHeight;
    int width = [_dataSource width];
    for (int y = 0; y < [_dataSource height]; y++) {
        screen_char_t *theLine = [_dataSource getLineAtIndex:y + firstVisibleLine];
        for (int x = 0; x < width; x++) {
            if (theLine && theLine[x].image && GetImageInfo(theLine[x].code) == image) {
                return YES;
            }
        }
    }
    return NO;
}

- (URLAction *)urlActionForClickAtX:(int)x y:(int)y {
    // I tried respecting hard newlines if that is a legal URL, but that's such a broad definition
    // that it doesn't work well. Hard EOLs mid-url are very common. Let's try always ignoring them.
    return [self urlActionForClickAtX:x
                                    y:y
               respectingHardNewlines:![self ignoreHardNewlinesInURLs]];
}

- (BOOL)ignoreHardNewlinesInURLs {
    if ([iTermAdvancedSettingsModel ignoreHardNewlinesInURLs]) {
        return YES;
    }
    return [self.delegate textViewInInteractiveApplication];
}

- (NSDragOperation)dragOperationForSender:(id<NSDraggingInfo>)sender {
    return [self dragOperationForSender:sender numberOfValidItems:NULL];
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
    BOOL uploadOK = ([types containsObject:NSFilenamesPboardType] && dropScpPath);

    // It's ok to paste if the the drag obejct is either a file or a string.
    BOOL pasteOK = !![[sender draggingPasteboard] availableTypeFromArray:@[ NSFilenamesPboardType, NSStringPboardType ]];

    const BOOL optionPressed = ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
    NSDragOperation sourceMask = [sender draggingSourceOperationMask];
    DLog(@"source mask=%@, optionPressed=%@, pasteOk=%@", @(sourceMask), @(optionPressed), @(pasteOK));
    if (!optionPressed && pasteOK && (sourceMask & (NSDragOperationGeneric | NSDragOperationCopy)) != 0) {
        DLog(@"Allowing a filename drag");
        // No modifier key was pressed and pasting is OK, so select the paste operation.
        NSArray *filenames = [pb filenamesOnPasteboardWithShellEscaping:YES];
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
            *numberOfValidItemsPtr = [[pb filenamesOnPasteboardWithShellEscaping:NO] count];
        }
        // You have to press option to get here so Copy is the only possibility.
        return NSDragOperationCopy;
    } else {
        // No luck.
        DLog(@"Not allowing drag");
        return NSDragOperationNone;
    }
}

+ (NSString *)usernameToDownloadFileOnHost:(NSString *)host {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = [NSString stringWithFormat:@"Enter username for host %@ to download file with scp", host];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease];
    [input setStringValue:NSUserName()];
    [alert setAccessoryView:input];
    [alert layout];
    [[alert window] makeFirstResponder:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        [input validateEditing];
        return [[input stringValue] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    }
    return nil;
}

// If iTerm2 is the handler for the scheme, then the profile is launched directly.
// Otherwise it's passed to the OS to launch.
- (void)openURL:(NSURL *)url inBackground:(BOOL)background {
    DLog(@"openURL:%@ inBackground:%@", url, @(background));

    Profile *profile = [[iTermLaunchServices sharedInstance] profileForScheme:[url scheme]];
    if (profile) {
        [_delegate launchProfileInCurrentTerminal:profile withURL:url.absoluteString];
    } else if (background) {
        [[NSWorkspace sharedWorkspace] openURLs:@[ url ]
                                           withAppBundleIdentifier:nil
                                           options:NSWorkspaceLaunchWithoutActivation
                                           additionalEventParamDescriptor:nil
                                           launchIdentifiers:nil];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)findUrlInString:(NSString *)aURLString andOpenInBackground:(BOOL)background {
    DLog(@"findUrlInString:%@", aURLString);
    NSRange range = [aURLString rangeOfURLInString];
    if (range.location == NSNotFound) {
        DLog(@"No URL found");
        return;
    }
    NSString *trimmedURLString = [aURLString substringWithRange:range];
    if (!trimmedURLString) {
        DLog(@"string is empty");
        return;
    }
    NSString* escapedString = [trimmedURLString stringByEscapingForURL];

    NSURL *url = [NSURL URLWithString:escapedString];
    [self openURL:url inBackground:background];
}

- (void)_dragImage:(iTermImageInfo *)imageInfo forEvent:(NSEvent *)theEvent
{
    NSImage *icon = [imageInfo imageWithCellSize:NSMakeSize(_charWidth, _lineHeight)];

    NSData *imageData = imageInfo.data;
    if (!imageData) {
        return;
    }

    // tell our app not switch windows (currently not working)
    [NSApp preventWindowOrdering];

    // drag from center of the image
    NSPoint dragPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];

    VT100GridCoord coord = VT100GridCoordMake((dragPoint.x - [iTermAdvancedSettingsModel terminalMargin]) / _charWidth,
                                              dragPoint.y / _lineHeight);
    screen_char_t* theLine = [_dataSource getLineAtIndex:coord.y];
    if (theLine &&
        coord.x < [_dataSource width] &&
        theLine[coord.x].image &&
        theLine[coord.x].code == imageInfo.code) {
        // Get the cell you clicked on (small y at top of view)
        VT100GridCoord pos = GetPositionOfImageInChar(theLine[coord.x]);

        // Get the top-left origin of the image in cell coords
        VT100GridCoord imageCellOrigin = VT100GridCoordMake(coord.x - pos.x,
                                                            coord.y - pos.y);

        // Compute the pixel coordinate of the image's top left point
        NSPoint imageTopLeftPoint = NSMakePoint(imageCellOrigin.x * _charWidth + [iTermAdvancedSettingsModel terminalMargin],
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
    [pbItem setString:aString forType:(NSString *)kUTTypeUTF8PlainText];
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

- (BOOL)_wasAnyCharSelected
{
    return [_oldSelection hasSelection];
}

- (void)_pointerSettingsChanged:(NSNotification *)notification {
    BOOL track = [pointer_ viewShouldTrackTouches];
    [self setAcceptsTouchEvents:track];
    [self setWantsRestingTouches:track];
    [threeFingerTapGestureRecognizer_ release];
    threeFingerTapGestureRecognizer_ = nil;
    if (track) {
        if ([self useThreeFingerTapGestureRecognizer]) {
            threeFingerTapGestureRecognizer_ = [[ThreeFingerTapGestureRecognizer alloc] initWithTarget:self
                                                                                              selector:@selector(threeFingerTap:)];
        }
    } else {
        _numTouches = 0;
    }
}

- (void)_settingsChanged:(NSNotification *)notification
{
    [self setNeedsDisplay:YES];
    _colorMap.dimOnlyText = [iTermPreferences boolForKey:kPreferenceKeyDimOnlyText];
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

- (void)setNeedsDisplayOnLine:(int)y inRange:(VT100GridRange)range {
    NSRect dirtyRect;
    const int x = range.location;
    const int maxX = range.location + range.length;

    dirtyRect.origin.x = [iTermAdvancedSettingsModel terminalMargin] + x * _charWidth;
    dirtyRect.origin.y = y * _lineHeight;
    dirtyRect.size.width = (maxX - x) * _charWidth;
    dirtyRect.size.height = _lineHeight;

    if (_drawingHelper.showTimestamps) {
        dirtyRect.size.width = self.visibleRect.size.width - dirtyRect.origin.x;
    }

    // Expand the rect in case we're drawing a changed cell with an oversize glyph.
    dirtyRect = [self rectWithHalo:dirtyRect];

    DLog(@"Line %d is dirty in range [%d, %d), set rect %@ dirty",
         y, x, maxX, [NSValue valueWithRect:dirtyRect]);
    [self setNeedsDisplayInRect:dirtyRect];
}

// WARNING: Do not call this function directly. Call
// -[refresh] instead, as it ensures scrollback overflow
// is dealt with so that this function can dereference
// [_dataSource dirty] correctly.
- (BOOL)updateDirtyRects {
    BOOL anythingIsBlinking = NO;
    BOOL foundDirty = NO;
    assert([_dataSource scrollbackOverflow] == 0);

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
    int WIDTH = [_dataSource width];

    // Any characters that changed selection status since the last update or
    // are blinking should be set dirty.
    anythingIsBlinking = [self _markChangedSelectionAndBlinkDirty:redrawBlink width:WIDTH];

    // Copy selection position to detect change in selected chars next call.
    [_oldSelection release];
    _oldSelection = [_selection copy];

    // Redraw lines with dirty characters
    int lineStart = [_dataSource numberOfLines] - [_dataSource height];
    int lineEnd = [_dataSource numberOfLines];
    // lineStart to lineEnd is the region that is the screen when the scrollbar
    // is at the bottom of the frame.

    [_dataSource setUseSavedGridIfAvailable:YES];
    long long totalScrollbackOverflow = [_dataSource totalScrollbackOverflow];
    int allDirty = [_dataSource isAllDirty] ? 1 : 0;
    [_dataSource resetAllDirty];

    VT100GridCoord cursorPosition = VT100GridCoordMake([_dataSource cursorX] - 1,
                                                       [_dataSource cursorY] - 1);
    if (_previousCursorCoord.x != cursorPosition.x ||
        _previousCursorCoord.y - totalScrollbackOverflow != cursorPosition.y) {
        // Mark previous and current cursor position dirty
        DLog(@"Mark previous cursor position %d,%lld dirty",
             _previousCursorCoord.x, _previousCursorCoord.y - totalScrollbackOverflow);
        int maxX = [_dataSource width] - 1;
        if (_drawingHelper.highlightCursorLine) {
            [_dataSource setLineDirtyAtY:_previousCursorCoord.y - totalScrollbackOverflow];
            DLog(@"Mark current cursor line %d dirty", cursorPosition.y);
            [_dataSource setLineDirtyAtY:cursorPosition.y];
        } else {
            [_dataSource setCharDirtyAtCursorX:MIN(maxX, _previousCursorCoord.x)
                                             Y:_previousCursorCoord.y - totalScrollbackOverflow];
            DLog(@"Mark current cursor position %d,%lld dirty", _previousCursorCoord.x,
                 _previousCursorCoord.y - totalScrollbackOverflow);
            [_dataSource setCharDirtyAtCursorX:MIN(maxX, cursorPosition.x) Y:cursorPosition.y];
        }
        // Set _previousCursorCoord to new cursor position
        _previousCursorCoord = VT100GridAbsCoordMake(cursorPosition.x,
                                                     cursorPosition.y + totalScrollbackOverflow);
    }

    // Remove results from dirty lines and mark parts of the view as needing display.
    if (allDirty) {
        foundDirty = YES;
        [_findOnPageHelper removeHighlightsInRange:NSMakeRange(lineStart + totalScrollbackOverflow,
                                                               lineEnd - lineStart)];
        [self setNeedsDisplayInRect:[self gridRect]];
    } else {
        for (int y = lineStart; y < lineEnd; y++) {
            VT100GridRange range = [_dataSource dirtyRangeForLine:y - lineStart];
            if (range.length > 0) {
                foundDirty = YES;
                [_findOnPageHelper removeHighlightsInRange:NSMakeRange(y + totalScrollbackOverflow, 1)];
                [_findOnPageHelper removeSearchResultsInRange:NSMakeRange(y + totalScrollbackOverflow, 1)];
                [self setNeedsDisplayOnLine:y inRange:range];
            }
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
        [_dataSource saveToDvr];
        [_delegate textViewInvalidateRestorableState];
        [_delegate textViewDidFindDirtyRects];
    }

    if (foundDirty && [_dataSource shouldSendContentsChangedNotification]) {
        _changedSinceLastExpose = YES;
        [_delegate textViewPostTabContentsChangedNotification];
    }

    [_dataSource setUseSavedGridIfAvailable:NO];

    // If you're viewing the scrollback area and it contains an animated gif it will need
    // to be redrawn periodically. The set of animated lines is added to while drawing and then
    // reset here.
    // TODO: Limit this to the columns that need to be redrawn.
    NSIndexSet *animatedLines = [_dataSource animatedLines];
    [animatedLines enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [self setNeedsDisplayOnLine:idx];
    }];
    [_dataSource resetAnimatedLines];

    return _blinkAllowed && anythingIsBlinking;
}

- (void)invalidateInputMethodEditorRect
{
    if ([_dataSource width] == 0) {
        return;
    }
    int imeLines = ([_dataSource cursorX] - 1 + [self inputMethodEditorLength] + 1) / [_dataSource width] + 1;

    NSRect imeRect = NSMakeRect([iTermAdvancedSettingsModel terminalMargin],
                                ([_dataSource cursorY] - 1 + [_dataSource numberOfLines] - [_dataSource height]) * _lineHeight,
                                [_dataSource width] * _charWidth,
                                imeLines * _lineHeight);
    imeRect = [self rectWithHalo:imeRect];
    [self setNeedsDisplayInRect:imeRect];
}

- (NSRect)rectWithHalo:(NSRect)rect {
    const int kHaloWidth = 4;
    rect.origin.x = rect.origin.x - _charWidth * kHaloWidth;
    rect.origin.y -= _lineHeight;
    rect.size.width = self.frame.size.width + _charWidth * 2 * kHaloWidth;
    rect.size.height += _lineHeight * 2;

    return rect;
}

- (void)moveSelectionEndpointToX:(int)x Y:(int)y locationInTextView:(NSPoint)locationInTextView
{
    if (_selection.live) {
        DLog(@"Move selection endpoint to %d,%d, coord=%@",
             x, y, [NSValue valueWithPoint:locationInTextView]);
        int width = [_dataSource width];
        if (locationInTextView.y == 0) {
            x = y = 0;
        } else if (locationInTextView.x < [iTermAdvancedSettingsModel terminalMargin] && _selection.liveRange.coordRange.start.y < y) {
            // complete selection of previous line
            x = width;
            y--;
        }
        if (y >= [_dataSource numberOfLines]) {
            y = [_dataSource numberOfLines] - 1;
        }
        [_selection moveSelectionEndpointTo:VT100GridCoordMake(x, y)];
        DLog(@"moveSelectionEndpoint. selection=%@", _selection);
    }
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

- (BOOL)_markChangedSelectionAndBlinkDirty:(BOOL)redrawBlink width:(int)width
{
    BOOL anyBlinkers = NO;
    // Visible chars that have changed selection status are dirty
    // Also mark blinking text as dirty if needed
    int lineStart = ([self visibleRect].origin.y + [iTermAdvancedSettingsModel terminalVMargin]) / _lineHeight;  // add VMARGIN because stuff under top margin isn't visible.
    int lineEnd = ceil(([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / _lineHeight);
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [_dataSource numberOfLines]) {
        lineEnd = [_dataSource numberOfLines];
    }
    for (int y = lineStart; y < lineEnd; y++) {
        if (_blinkAllowed) {
            // First, mark blinking chars as dirty.
            screen_char_t* theLine = [_dataSource getLineAtIndex:y];
            for (int x = 0; x < width; x++) {
                BOOL charBlinks = [self charBlinks:theLine[x]];
                anyBlinkers |= charBlinks;
                BOOL blinked = redrawBlink && charBlinks;
                if (blinked) {
                    NSRect dirtyRect = [self visibleRect];
                    dirtyRect.origin.y = y * _lineHeight;
                    dirtyRect.size.height = _lineHeight;
                    if (gDebugLogging) {
                        DLog(@"Found blinking char on line %d", y);
                    }
                    [self setNeedsDisplayInRect:[self rectWithHalo:dirtyRect]];
                    break;
                }
            }
        }

        // Now mark chars whose selection status has changed as needing display.
        NSIndexSet *areSelected = [_selection selectedIndexesOnLine:y];
        NSIndexSet *wereSelected = [_oldSelection selectedIndexesOnLine:y];
        if (![areSelected isEqualToIndexSet:wereSelected]) {
            // Just redraw the whole line for simplicity.
            NSRect dirtyRect = [self visibleRect];
            dirtyRect.origin.y = y * _lineHeight;
            dirtyRect.size.height = _lineHeight;
            if (gDebugLogging) {
                DLog(@"found selection change on line %d", y);
            }
            [self setNeedsDisplayInRect:[self rectWithHalo:dirtyRect]];
        }
    }
    return anyBlinkers;
}

#pragma mark - iTermSelectionDelegate

- (void)selectionDidChange:(iTermSelection *)selection {
    [_delegate refresh];
    if (!_selection.live && selection.hasSelection) {
        const NSInteger MAX_SELECTION_SIZE = 10 * 1000 * 1000;
        NSString *selection = [self selectedTextWithCappedAtSize:MAX_SELECTION_SIZE minimumLineNumber:0];
        if (selection.length == MAX_SELECTION_SIZE) {
            selection = nil;
        }
        [[iTermController sharedInstance] setLastSelection:selection];
    }
    DLog(@"Selection did change: selection=%@. stack=%@",
         selection, [NSThread callStackSymbols]);
}

- (VT100GridRange)selectionRangeOfTerminalNullsOnLine:(int)lineNumber {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    int length = [extractor lengthOfLine:lineNumber];
    int width = [_dataSource width];
    return VT100GridRangeMake(length, width - length);
}

- (VT100GridWindowedRange)selectionRangeForParentheticalAt:(VT100GridCoord)coord {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    [extractor restrictToLogicalWindowIncludingCoord:coord];
    return [extractor rangeOfParentheticalSubstringAtLocation:coord];
}

- (VT100GridWindowedRange)selectionRangeForWordAt:(VT100GridCoord)coord {
    VT100GridWindowedRange range;
    [self getWordForX:coord.x
                    y:coord.y
                range:&range
      respectDividers:[[iTermController sharedInstance] selectionRespectsSoftBoundaries]];
    return range;
}

- (VT100GridWindowedRange)selectionRangeForSmartSelectionAt:(VT100GridCoord)coord {
    VT100GridWindowedRange range;
    [self smartSelectAtX:coord.x
                       y:coord.y
                      to:&range
        ignoringNewlines:NO
          actionRequired:NO
         respectDividers:[[iTermController sharedInstance] selectionRespectsSoftBoundaries]];
    return range;
}

- (VT100GridWindowedRange)selectionRangeForWrappedLineAt:(VT100GridCoord)coord {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    BOOL respectDividers = [[iTermController sharedInstance] selectionRespectsSoftBoundaries];
    if (respectDividers) {
        [extractor restrictToLogicalWindowIncludingCoord:coord];
    }
    return [extractor rangeForWrappedLineEncompassing:coord
                                 respectContinuations:NO
                                             maxChars:-1];
}

- (int)selectionViewportWidth {
    return [_dataSource width];
}

- (VT100GridWindowedRange)selectionRangeForLineAt:(VT100GridCoord)coord {
    BOOL respectDividers = [[iTermController sharedInstance] selectionRespectsSoftBoundaries];
    if (respectDividers) {
        iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
        [extractor restrictToLogicalWindowIncludingCoord:coord];
        return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(extractor.logicalWindow.location,
                                                                  coord.y,
                                                                  VT100GridRangeMax(extractor.logicalWindow) + 1,
                                                                  coord.y),
                                          extractor.logicalWindow.location,
                                          extractor.logicalWindow.length);
    }
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, coord.y, [_dataSource width], coord.y), 0, 0);
}

- (VT100GridCoord)selectionPredecessorOfCoord:(VT100GridCoord)coord {
    screen_char_t *theLine;
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

        theLine = [_dataSource getLineAtIndex:coord.y];
    } while (theLine[coord.x].code == DWC_RIGHT);
    return coord;
}

- (NSIndexSet *)selectionIndexesOnLine:(int)line
                   containingCharacter:(unichar)c
                               inRange:(NSRange)range {
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_dataSource];
    return [extractor indexesOnLine:line containingCharacter:c inRange:range];
}

#pragma mark - iTermColorMapDelegate

- (void)colorMap:(iTermColorMap *)colorMap didChangeColorForKey:(iTermColorMapKey)theKey {
    if (theKey == kColorMapBackground) {
        [self updateScrollerForBackgroundColor];
        [[self enclosingScrollView] setBackgroundColor:[colorMap colorForKey:theKey]];
        [self recomputeBadgeLabel];
        [_delegate textViewBackgroundColorDidChange];
    } else if (theKey == kColorMapForeground) {
        [self recomputeBadgeLabel];
    } else if (theKey == kColorMapSelection) {
        _drawingHelper.unfocusedSelectionColor = [[_colorMap colorForKey:theKey] colorDimmedBy:2.0/3.0
                                                                              towardsGrayLevel:0.5];
    }
    [self setNeedsDisplay:YES];
}

- (void)colorMap:(iTermColorMap *)colorMap
    dimmingAmountDidChangeTo:(double)dimmingAmount {
    [[self superview] setNeedsDisplay:YES];
}

- (void)colorMap:(iTermColorMap *)colorMap
    mutingAmountDidChangeTo:(double)mutingAmount {
    [[self superview] setNeedsDisplay:YES];
}

#pragma mark - iTermInidcatorsHelperDelegate

- (NSColor *)indicatorFullScreenFlashColor {
    return [self defaultTextColor];
}

#pragma mark - Mouse reporting

- (NSRect)liveRect {
    int numLines = [_dataSource numberOfLines];
    NSRect rect;
    int height = [_dataSource height];
    rect.origin.y = numLines - height;
    rect.origin.y *= _lineHeight;
    rect.origin.x = [iTermAdvancedSettingsModel terminalMargin];
    rect.size.width = _charWidth * [_dataSource width];
    rect.size.height = _lineHeight * [_dataSource height];
    return rect;
}

- (BOOL)shouldReportMouseEvent:(NSEvent *)event at:(NSPoint)point {
    NSRect liveRect = [self liveRect];
    if (!NSPointInRect(point, liveRect)) {
        return NO;
    }
    if ((event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp) && _mouseDownWasFirstMouse) {
        return NO;
    }
    if ((event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp) && self.window.firstResponder != self) {
        return NO;
    }
    if (event.type == NSEventTypeScrollWheel) {
        return ([self xtermMouseReporting] && [self xtermMouseReportingAllowMouseWheel]);
    } else {
        PTYTextView* frontTextView = [[iTermController sharedInstance] frontTextView];
        return (frontTextView == self && [self xtermMouseReporting]);
    }
}

- (MouseButtonNumber)mouseReportingButtonNumberForEvent:(NSEvent *)event {
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
            return MOUSE_BUTTON_MIDDLE;

        case NSEventTypeScrollWheel:
            if ([event scrollingDeltaY] > 0) {
                return MOUSE_BUTTON_SCROLLDOWN;
            } else {
                return MOUSE_BUTTON_SCROLLUP;
            }

        default:
            return MOUSE_BUTTON_NONE;
    }
}

// Returns YES if the mouse event should not be handled natively.
- (BOOL)reportMouseEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];

    if (![self shouldReportMouseEvent:event at:point]) {
        return NO;
    }

    NSRect liveRect = [self liveRect];
    VT100GridCoord coord = VT100GridCoordMake((point.x - liveRect.origin.x) / _charWidth,
                                              (point.y - liveRect.origin.y) / _lineHeight);
    coord.x = MAX(0, coord.x);
    coord.y = MAX(0, coord.y);

    return [_delegate textViewReportMouseEvent:event.type
                                     modifiers:event.modifierFlags
                                        button:[self mouseReportingButtonNumberForEvent:event]
                                    coordinate:coord
                                        deltaY:[_scrollAccumulator deltaYForEvent:event lineHeight:self.enclosingScrollView.verticalLineScroll]];
}

#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationEvery;
}

#pragma mark - Selection Scroll

- (void)selectionScrollWillStart {
    PTYScroller *scroller = (PTYScroller *)self.enclosingScrollView.verticalScroller;
    scroller.userScroll = YES;
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
            color = [color colorWithAlphaComponent:0.5];
        }
    }
    return color;
}

- (BOOL)charBlinks:(screen_char_t)sct {
    return self.blinkAllowed && sct.blink;
}

- (iTermColorMapKey)colorMapKeyForCode:(int)theIndex
                                 green:(int)green
                                  blue:(int)blue
                             colorMode:(ColorMode)theMode
                                  bold:(BOOL)isBold
                          isBackground:(BOOL)isBackground {
    BOOL isBackgroundForDefault = isBackground;
    switch (theMode) {
        case ColorModeAlternate:
            switch (theIndex) {
                case ALTSEM_SELECTED:
                    if (isBackground) {
                        return kColorMapSelection;
                    } else {
                        return kColorMapSelectedText;
                    }
                case ALTSEM_CURSOR:
                    if (isBackground) {
                        return kColorMapCursor;
                    } else {
                        return kColorMapCursorText;
                    }
                case ALTSEM_REVERSED_DEFAULT:
                    isBackgroundForDefault = !isBackgroundForDefault;
                    // Fall through.
                case ALTSEM_DEFAULT:
                    if (isBackgroundForDefault) {
                        return kColorMapBackground;
                    } else {
                        if (isBold && self.useBoldColor) {
                            return kColorMapBold;
                        } else {
                            return kColorMapForeground;
                        }
                    }
            }
            break;
        case ColorMode24bit:
            return [iTermColorMap keyFor8bitRed:theIndex green:green blue:blue];
        case ColorModeNormal:
            // Render bold text as bright. The spec (ECMA-48) describes the intense
            // display setting (esc[1m) as "bold or bright". We make it a
            // preference.
            if (isBold &&
                self.useBoldColor &&
                (theIndex < 8) &&
                !isBackground) { // Only colors 0-7 can be made "bright".
                theIndex |= 8;  // set "bright" bit.
            }
            return kColorMap8bitBase + (theIndex & 0xff);

        case ColorModeInvalid:
            return kColorMapInvalid;
    }
    NSAssert(ok, @"Bogus color mode %d", (int)theMode);
    return kColorMapInvalid;
}

#pragma mark - iTermTextDrawingHelperDelegate

- (void)drawingHelperDrawBackgroundImageInRect:(NSRect)rect
                        blendDefaultBackground:(BOOL)blend {
    [_delegate textViewDrawBackgroundImageInView:self viewRect:rect blendDefaultBackground:blend];
}

- (VT100ScreenMark *)drawingHelperMarkOnLine:(int)line {
    return [_dataSource markOnLine:line];
}

- (screen_char_t *)drawingHelperLineAtIndex:(int)line {
    return [_dataSource getLineAtIndex:line];
}

- (screen_char_t *)drawingHelperLineAtScreenIndex:(int)line {
    return [_dataSource getLineAtScreenIndex:line];
}

- (screen_char_t *)drawingHelperCopyLineAtIndex:(int)line toBuffer:(screen_char_t *)buffer {
    return [_dataSource getLineAtIndex:line withBuffer:buffer];
}

- (iTermTextExtractor *)drawingHelperTextExtractor {
    return [[[iTermTextExtractor alloc] initWithDataSource:_dataSource] autorelease];
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
                             renderItalic:(BOOL *)renderItalic {
    return [self getFontForChar:ch
                      isComplex:isComplex
                     renderBold:renderBold
                   renderItalic:renderItalic];
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

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSInteger)accessibilityLineForIndex:(NSInteger)index {
    return [_accessibilityHelper lineForIndex:index];
}

- (NSRange)accessibilityRangeForLine:(NSInteger)line {
    return [_accessibilityHelper rangeForLine:line];
}

- (NSString *)accessibilityStringForRange:(NSRange)range {
    return [_accessibilityHelper stringForRange:range];
}

- (NSRange)accessibilityRangeForPosition:(NSPoint)point {
    return [_accessibilityHelper rangeForPosition:point];
}

- (NSRange)accessibilityRangeForIndex:(NSInteger)index {
    return [_accessibilityHelper rangeOfIndex:index];
}

- (NSRect)accessibilityFrameForRange:(NSRange)range {
    return [_accessibilityHelper boundsForRange:range];
}

- (NSAttributedString *)accessibilityAttributedStringForRange:(NSRange)range {
    return [_accessibilityHelper attributedStringForRange:range];
}

- (NSAccessibilityRole)accessibilityRole {
    return [_accessibilityHelper role];
}

- (NSString *)accessibilityRoleDescription {
    return [_accessibilityHelper roleDescription];
}

- (NSString *)accessibilityHelp {
    return [_accessibilityHelper help];
}

- (BOOL)isAccessibilityFocused {
    return [_accessibilityHelper focused];
}

- (NSString *)accessibilityLabel {
    return [_accessibilityHelper label];
}

- (id)accessibilityValue {
    return [_accessibilityHelper allText];
}

- (NSInteger)accessibilityNumberOfCharacters {
    return [_accessibilityHelper numberOfCharacters];
}

- (NSString *)accessibilitySelectedText {
    return [_accessibilityHelper selectedText];
}

- (NSRange)accessibilitySelectedTextRange {
    return [_accessibilityHelper selectedTextRange];
}

- (NSArray<NSValue *> *)accessibilitySelectedTextRanges {
    return [_accessibilityHelper selectedTextRanges];
}

- (NSInteger)accessibilityInsertionPointLineNumber {
    return [_accessibilityHelper insertionPointLineNumber];
}

- (NSRange)accessibilityVisibleCharacterRange {
    return [_accessibilityHelper visibleCharacterRange];
}

- (NSString *)accessibilityDocument {
    return [[_accessibilityHelper currentDocumentURL] absoluteString];
}

- (void)setAccessibilitySelectedTextRange:(NSRange)accessibilitySelectedTextRange {
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

- (VT100GridCoord)accessibilityHelperCoordForPoint:(NSPoint)screenPosition {
    NSRect screenRect = NSMakeRect(screenPosition.x,
                                   screenPosition.y,
                                   0,
                                   0);
    NSRect windowRect = [self.window convertRectFromScreen:screenRect];
    NSPoint locationInTextView = [self convertPoint:windowRect.origin fromView:nil];
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    int x = (locationInTextView.x - [iTermAdvancedSettingsModel terminalMargin] - visibleRect.origin.x) / _charWidth;
    int y = locationInTextView.y / _lineHeight;
    return VT100GridCoordMake(x, [self accessibilityHelperAccessibilityLineNumberForLineNumber:y]);
}

- (NSRect)accessibilityHelperFrameForCoordRange:(VT100GridCoordRange)coordRange {
    coordRange.start.y = [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.start.y];
    coordRange.end.y = [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.end.y];
    NSRect result = NSMakeRect(MAX(0, floor(coordRange.start.x * _charWidth + [iTermAdvancedSettingsModel terminalMargin])),
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
    coordRange.start.y =
        [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.start.y];
    coordRange.end.y =
        [self accessibilityHelperLineNumberForAccessibilityLineNumber:coordRange.end.y];
    [_selection clearSelection];
    [_selection beginSelectionAt:coordRange.start
                            mode:kiTermSelectionModeCharacter
                          resume:NO
                          append:NO];
    [_selection moveSelectionEndpointTo:coordRange.end];
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

    VT100GridCoordRange coordRange = sub.range.coordRange;
    int minY = _dataSource.numberOfLines - _dataSource.height;
    if (coordRange.start.y < minY) {
        coordRange.start.y = 0;
        coordRange.start.x = 0;
    } else {
        coordRange.start.y -= minY;
    }
    if (coordRange.end.y < minY) {
        return [self accessibilityRangeOfCursor];
    } else {
        coordRange.end.y -= minY;
    }
    return coordRange;
}

- (NSString *)accessibilityHelperSelectedText {
    return [self selectedTextAttributed:NO
                           cappedAtSize:0
                      minimumLineNumber:[self accessibilityHelperLineNumberForAccessibilityLineNumber:0]];
}

- (NSURL *)accessibilityHelperCurrentDocumentURL {
    return [_delegate textViewCurrentLocation];
}

- (screen_char_t *)accessibilityHelperLineAtIndex:(int)accessibilityIndex {
    return [_dataSource getLineAtIndex:[self accessibilityHelperLineNumberForAccessibilityLineNumber:accessibilityIndex]];
}

- (int)accessibilityHelperWidth {
    return [_dataSource width];
}

- (int)accessibilityHelperNumberOfLines {
    return MIN([iTermAdvancedSettingsModel numberOfLinesForAccessibility],
               [_dataSource numberOfLines]);
}

#pragma mark - NSMenuDelegate

- (void)menuDidClose:(NSMenu *)menu {
    self.savedSelectedText = nil;
}

#pragma mark - iTermAltScreenMouseScrollInfererDelegate

- (void)altScreenMouseScrollInfererDidInferScrollingIntent:(BOOL)isTrying {
    [_delegate textViewThinksUserIsTryingToSendArrowKeysWithScrollWheel:isTrying];
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
    NSPopover *popover = notification.object;
    iTermWebViewWrapperViewController *viewController = (iTermWebViewWrapperViewController *)popover.contentViewController;
    [viewController terminateWebView];

}

@end

