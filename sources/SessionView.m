// This view contains a session's scrollview.

#import "SessionView.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermAnnouncementViewController.h"
#import "iTermPreferences.h"
#import "NSView+iTerm.h"
#import "MovePaneController.h"
#import "PSMTabDragAssistant.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "SessionTitleView.h"
#import "SplitSelectionView.h"

static int nextViewId;
static const double kTitleHeight = 22;

// Last time any window was resized TODO(georgen):it would be better to track per window.
static NSDate* lastResizeDate_;

@interface SessionView () <iTermAnnouncementDelegate>
@property(nonatomic, retain) PTYScrollView *scrollview;
@end

@implementation SessionView {
    NSMutableArray *_announcements;
    BOOL _inDealloc;
    iTermAnnouncementViewController *_currentAnnouncement;

    BOOL _dim;
    BOOL _backgroundDimmed;

    // Find window
    FindViewController *_findView;

    // Saved size for unmaximizing.
    NSSize _savedSize;

    // When moving a pane, a view is put over all sessions to help the user
    // choose how to split the destination.
    SplitSelectionView *_splitSelectionView;

    BOOL _showTitle;
    SessionTitleView *_title;
    
    BOOL _inAddSubview;
}

+ (double)titleHeight {
    return kTitleHeight;
}

+ (void)initialize {
    if (self == [SessionView self]) {
        lastResizeDate_ = [[NSDate date] retain];
    }
}

+ (void)windowDidResize {
    [lastResizeDate_ release];
    lastResizeDate_ = [[NSDate date] retain];
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:@[ iTermMovePaneDragType, @"com.iterm2.psm.controlitem" ]];
        [lastResizeDate_ release];
        lastResizeDate_ = [[NSDate date] retain];
        _announcements = [[NSMutableArray alloc] init];

        // Set up find view
        _findView = [[FindViewController alloc] initWithNibName:@"FindView" bundle:nil];
        [[_findView view] setHidden:YES];
        [self addSubview:[_findView view]];
        NSRect aRect = [self frame];
        [_findView setFrameOrigin:NSMakePoint(aRect.size.width - [[_findView view] frame].size.width - 30,
                                                     aRect.size.height - [[_findView view] frame].size.height)];
        
        // Assign a globally unique view ID.
        _viewId = nextViewId++;

        // Allocate a scrollview
        _scrollview = [[PTYScrollView alloc] initWithFrame:NSMakeRect(0,
                                                                      0,
                                                                      aRect.size.width,
                                                                      aRect.size.height)
                                       hasVerticalScroller:NO];
        [_scrollview setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

        // assign the main view
        [self addSubview:_scrollview];

        // setCopiesOnScroll is off because there is a top and bottom margin in the PTYTextView and
        // we would not want that copied.
        [[_scrollview contentView] setCopiesOnScroll:NO];
    }
    return self;
}

- (void)dealloc {
    _inDealloc = YES;
    [_scrollview release];
    [_title removeFromSuperview];
    [self unregisterDraggedTypes];
    [_currentAnnouncement dismiss];
    [_currentAnnouncement release];
    [_announcements release];
    while (self.trackingAreas.count) {
        [self removeTrackingArea:self.trackingAreas[0]];
    }
    [super dealloc];
}

- (void)addSubview:(NSView *)aView {
    BOOL wasRunning = _inAddSubview;
    _inAddSubview = YES;
    if (!wasRunning && _findView && aView != [_findView view]) {
        [super addSubview:aView positioned:NSWindowBelow relativeTo:[_findView view]];
    } else {
        [super addSubview:aView];
    }
    _inAddSubview = NO;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize {
    [self updateLayout];
}

- (void)updateLayout {
    if ([_delegate sessionViewShouldUpdateSubviewsFramesAutomatically]) {
        if (self.showTitle) {
            [self updateTitleFrame];
        } else {
            [self updateScrollViewFrame];
            [self updateFindViewFrame];
        }
    }
}

- (void)setDelegate:(id<iTermSessionViewDelegate>)delegate {
    _delegate = delegate;
    [_delegate sessionViewDimmingAmountDidChange:[self adjustedDimmingAmount]];
}

- (void)_dimShadeToDimmingAmount:(float)newDimmingAmount {
    [_delegate sessionViewDimmingAmountDidChange:newDimmingAmount];
}

- (double)dimmedDimmingAmount {
    return [iTermPreferences floatForKey:kPreferenceKeyDimmingAmount];
}

- (double)adjustedDimmingAmount {
    int x = 0;
    if (_dim) {
        x++;
    }
    if (_backgroundDimmed) {
        x++;
    }
    double scale[] = { 0, 1.0, 1.5 };
    double amount = scale[x] * [self dimmedDimmingAmount];
    // Cap amount within reasonable bounds. Before 1.1, dimming amount was only changed by
    // twiddling the prefs file so it could have all kinds of crazy values.
    amount = MIN(0.9, amount);
    amount = MAX(0, amount);

    return amount;
}

- (void)updateDim {
    double amount = [self adjustedDimmingAmount];

    [self _dimShadeToDimmingAmount:amount];
    [_title setDimmingAmount:amount];
}

- (void)setDimmed:(BOOL)isDimmed {
    if (isDimmed == _dim) {
        return;
    }
    if ([_delegate sessionViewIsVisible]) {
        _dim = isDimmed;
        [self updateDim];
    } else {
        _dim = isDimmed;
    }
}

- (void)setBackgroundDimmed:(BOOL)backgroundDimmed {
    BOOL orig = _backgroundDimmed;
    if ([iTermPreferences boolForKey:kPreferenceKeyDimBackgroundWindows]) {
        _backgroundDimmed = backgroundDimmed;
    } else {
        _backgroundDimmed = NO;
    }
    if (_backgroundDimmed != orig) {
        [self updateDim];
        [self setNeedsDisplay:YES];
    }
}

// It's very expensive for PTYTextView to own its own tracking events because its frame changes
// constantly, plus it can miss mouse exit events and spurious mouse enter events (issue 3345).
// I beleive it also caused hangs (issue 3974).
- (void)updateTrackingAreas {
    if ([self window]) {
        int trackingOptions;
        trackingOptions = (NSTrackingMouseEnteredAndExited |
                           NSTrackingActiveAlways |
                           NSTrackingEnabledDuringMouseDrag |
                           NSTrackingMouseMoved);
        while (self.trackingAreas.count) {
            [self removeTrackingArea:self.trackingAreas[0]];
        }
        NSTrackingArea *trackingArea = [[[NSTrackingArea alloc] initWithRect:self.bounds
                                                                     options:trackingOptions
                                                                       owner:self
                                                                    userInfo:nil] autorelease];
        [self addTrackingArea:trackingArea];
    }
}

- (void)mouseEntered:(NSEvent *)theEvent {
    [_delegate sessionViewMouseEntered:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent {
    [_delegate sessionViewMouseExited:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent {
    [_delegate sessionViewMouseMoved:theEvent];
}

- (void)rightMouseDown:(NSEvent*)event {
    if (!_splitSelectionView) {
        static int inme;
        if (inme) {
            // Avoid infinite recursion. Not quite sure why this happens, but a call
            // to -[PTYTextView rightMouseDown:] will sometimes (after a
            // few steps through the OS) bring you back here. It happens when randomly touching
            // a bunch of fingers on the trackpad.
            return;
        }
        ++inme;
        [_delegate sessionViewRightMouseDown:event];
        --inme;
    }
}


- (void)mouseDown:(NSEvent*)event {
    static int inme;
    if (inme) {
        // Avoid infinite recursion. Not quite sure why this happens, but a call
        // to [_title mouseDown:] or [super mouseDown:] will sometimes (after a
        // few steps through the OS) bring you back here. It only happens
        // consistently when dragging the pane title bar, but it happens inconsitently
        // with clicks in the title bar too.
        return;
    }
    ++inme;
    // A click on the very top of the screen while in full screen mode may not be
    // in any subview!
    NSPoint p = [NSEvent mouseLocation];
    NSPoint pointInSessionView;
    NSRect windowRect = [self.window convertRectFromScreen:NSMakeRect(p.x, p.y, 0, 0)];
    pointInSessionView = [self convertRect:windowRect fromView:nil].origin;
    DLog(@"Point in screen coords=%@, point in window coords=%@, point in session view=%@",
         NSStringFromPoint(p),
         NSStringFromPoint(windowRect.origin),
         NSStringFromPoint(pointInSessionView));
    if (_title && NSPointInRect(pointInSessionView, [_title frame])) {
        [_title mouseDown:event];
        --inme;
        return;
    }
    if (_splitSelectionView) {
        [_splitSelectionView mouseDown:event];
    } else if (NSPointInRect(pointInSessionView, [[self scrollview] frame]) &&
               [_delegate sessionViewShouldForwardMouseDownToSuper:event]) {
        [super mouseDown:event];
    }
    --inme;
}

- (FindViewController*)findViewController {
    return _findView;
}

- (void)setFrameSize:(NSSize)frameSize {
    [self updateAnnouncementFrame];
    [super setFrameSize:frameSize];
    if (frameSize.width < 340) {
        [[_findView view] setFrameSize:NSMakeSize(MAX(150, frameSize.width - 50),
                                                  [[_findView view] frame].size.height)];
        [_findView setFrameOrigin:NSMakePoint(frameSize.width - [[_findView view] frame].size.width - 30,
                                              frameSize.height - [[_findView view] frame].size.height)];
    } else {
        [[_findView view] setFrameSize:NSMakeSize(290,
                                                  [[_findView view] frame].size.height)];
        [_findView setFrameOrigin:NSMakePoint(frameSize.width - [[_findView view] frame].size.width - 30,
                                              frameSize.height - [[_findView view] frame].size.height)];
    }
}

+ (NSDate*)lastResizeDate {
    return lastResizeDate_;
}

// This is called as part of the live resizing protocol when you let up the mouse button.
- (void)viewDidEndLiveResize {
    [lastResizeDate_ release];
    lastResizeDate_ = [[NSDate date] retain];
}

- (void)saveFrameSize {
    _savedSize = [self frame].size;
}

- (void)restoreFrameSize {
    [self setFrameSize:_savedSize];
}

- (void)createSplitSelectionView:(BOOL)cancelOnly move:(BOOL)move session:(id)session {
    _splitSelectionView = [[SplitSelectionView alloc] initAsCancelOnly:cancelOnly
                                                             withFrame:NSMakeRect(0,
                                                                                  0,
                                                                                  [self frame].size.width,
                                                                                  [self frame].size.height)
                                                               session:session
                                                              delegate:[MovePaneController sharedInstance]
                                                                  move:move];
    [_splitSelectionView setFrameOrigin:NSMakePoint(0, 0)];
    [_splitSelectionView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [self addSubview:_splitSelectionView];
    [_splitSelectionView release];
}

- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move session:(id)session {
    switch (mode) {
        case kSplitSelectionModeOn:
            if (_splitSelectionView) {
                return;
            }
            [self createSplitSelectionView:NO move:move session:session];
            break;

        case kSplitSelectionModeOff:
            [_splitSelectionView removeFromSuperview];
            _splitSelectionView = nil;
            break;

        case kSplitSelectionModeCancel:
            [self createSplitSelectionView:YES move:move session:session];
            break;
    }
}

- (void)drawBackgroundInRect:(NSRect)rect {
    [_delegate sessionViewDrawBackgroundImageInView:self
                                           viewRect:rect
                             blendDefaultBackground:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    // Fill in background color in the area around a scrollview if it's smaller
    // than the session view.
    [super drawRect:dirtyRect];
    PTYScrollView *scrollView = [self scrollview];
    NSRect svFrame = [scrollView frame];
    if (svFrame.size.width < self.frame.size.width) {
        double widthDiff = self.frame.size.width - svFrame.size.width;
        [self drawBackgroundInRect:NSMakeRect(self.frame.size.width - widthDiff,
                                              0,
                                              widthDiff,
                                              self.frame.size.height)];
    }
    if (svFrame.origin.y != 0) {
        [self drawBackgroundInRect:NSMakeRect(0, 0, self.frame.size.width, svFrame.origin.y)];
    }
    CGFloat maxY = svFrame.origin.y + svFrame.size.height;
    if (maxY < self.frame.size.height) {
        [self drawBackgroundInRect:NSMakeRect(dirtyRect.origin.x,
                                              maxY,
                                              dirtyRect.size.width,
                                              self.frame.size.height - maxY)];
    }
}

- (NSRect)contentRect {
    if (_showTitle) {
        return NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height - kTitleHeight);
    } else {
        return self.frame;
    }
}

- (void)createSplitSelectionView {
    NSRect frame = self.frame;
    _splitSelectionView = [[SplitSelectionView alloc] initWithFrame:NSMakeRect(0,
                                                                               0,
                                                                               frame.size.width,
                                                                               frame.size.height)];
    [self addSubview:_splitSelectionView];
    [_splitSelectionView release];
    [[self window] orderFront:nil];
}

- (SplitSessionHalf)removeSplitSelectionView {
    SplitSessionHalf half = [_splitSelectionView half];
    [_splitSelectionView removeFromSuperview];
    _splitSelectionView = nil;
    return half;
}

#pragma mark NSDraggingSource protocol

- (void)draggedImage:(NSImage *)draggedImage movedTo:(NSPoint)screenPoint {
    [[NSCursor closedHandCursor] set];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal {
    return (isLocal ? NSDragOperationMove : NSDragOperationNone);
}

- (BOOL)ignoreModifierKeysWhileDragging {
    return YES;
}

- (void)draggedImage:(NSImage *)anImage
             endedAt:(NSPoint)aPoint
           operation:(NSDragOperation)operation {
    if (![[MovePaneController sharedInstance] dragFailed]) {
        [[MovePaneController sharedInstance] dropInSession:nil half:kNoHalf atPoint:aPoint];
    }
}

#pragma mark NSDraggingDestination protocol

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender {
    return [_delegate sessionViewDraggingEntered:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    [_splitSelectionView removeFromSuperview];
    _splitSelectionView = nil;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    if ([_delegate sessionViewShouldSplitSelectionAfterDragUpdate:sender]) {
        NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
        [_splitSelectionView updateAtPoint:point];
    }
    return NSDragOperationMove;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [_delegate sessionViewPerformDragOperation:sender];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)wantsPeriodicDraggingUpdates {
    return YES;
}

- (BOOL)showTitle {
    return _showTitle;
}

- (BOOL)setShowTitle:(BOOL)value adjustScrollView:(BOOL)adjustScrollView {
    if (value == _showTitle) {
        return NO;
    }
    _showTitle = value;
    PTYScrollView *scrollView = [self scrollview];
    NSRect frame = [scrollView frame];
    if (_showTitle) {
        frame.size.height -= kTitleHeight;
        _title = [[[SessionTitleView alloc] initWithFrame:NSMakeRect(0,
                                                                     self.frame.size.height - kTitleHeight,
                                                                     self.frame.size.width,
                                                                     kTitleHeight)] autorelease];
        if (adjustScrollView) {
            [_title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        }
        _title.delegate = self;
        [_title setDimmingAmount:[self adjustedDimmingAmount]];
        [self addSubview:_title];
    } else {
        frame.size.height += kTitleHeight;
        [_title removeFromSuperview];
        _title = nil;
    }
    if (adjustScrollView) {
        [scrollView setFrame:frame];
    } else {
        [self updateTitleFrame];
    }
    [self setTitle:[_delegate sessionViewTitle]];
    [self updateScrollViewFrame];
    return YES;
}

- (void)setOrdinal:(int)ordinal {
    _ordinal = ordinal;
    _title.ordinal = ordinal;
}

- (NSSize)compactFrame {
    NSSize cellSize = [_delegate sessionViewCellSize];
    VT100GridSize gridSize = [_delegate sessionViewGridSize];
    NSSize dim = NSMakeSize(gridSize.width, gridSize.height);
    NSSize innerSize = NSMakeSize(cellSize.width * dim.width + MARGIN * 2,
                                  cellSize.height * dim.height + VMARGIN * 2);
    const BOOL hasScrollbar = [[self scrollview] hasVerticalScroller];
    NSSize size =
        [PTYScrollView frameSizeForContentSize:innerSize
                       horizontalScrollerClass:nil
                         verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                                    borderType:NSNoBorder
                                   controlSize:NSRegularControlSize
                                 scrollerStyle:[[self scrollview] scrollerStyle]];

    if (_showTitle) {
        size.height += kTitleHeight;
    }
    return size;
}

- (NSSize)maximumPossibleScrollViewContentSize {
    NSSize size = self.frame.size;
    DLog(@"maximumPossibleScrollViewContentSize. size=%@", [NSValue valueWithSize:size]);
    if (_showTitle) {
        size.height -= kTitleHeight;
        DLog(@"maximumPossibleScrollViewContentSize: sub title height. size=%@", [NSValue valueWithSize:size]);
    }

    Class verticalScrollerClass = [[[self scrollview] verticalScroller] class];
    if (![[self scrollview] hasVerticalScroller]) {
        verticalScrollerClass = nil;
    }
    NSSize contentSize =
            [NSScrollView contentSizeForFrameSize:size
                          horizontalScrollerClass:nil
                            verticalScrollerClass:verticalScrollerClass
                                       borderType:[[self scrollview] borderType]
                                      controlSize:NSRegularControlSize
                                    scrollerStyle:[[[self scrollview] verticalScroller] scrollerStyle]];
    return contentSize;
}

- (void)updateTitleFrame {
    NSRect aRect = [self frame];
    if (_showTitle) {
        [_title setFrame:NSMakeRect(0,
                                    aRect.size.height - kTitleHeight,
                                    aRect.size.width,
                                    kTitleHeight)];
    }
    [self updateScrollViewFrame];
    [self updateFindViewFrame];
}

- (void)updateFindViewFrame {
    NSRect aRect = self.frame;
    [_findView setFrameOrigin:NSMakePoint(aRect.size.width - [[_findView view] frame].size.width - 30,
                                          aRect.size.height - [[_findView view] frame].size.height)];
}

- (void)updateScrollViewFrame {
    CGFloat titleHeight = _showTitle ? _title.frame.size.height : 0;
    NSSize proposedSize = NSMakeSize(self.frame.size.width,
                                     self.frame.size.height - titleHeight);
    NSSize size = [_delegate sessionViewScrollViewWillResize:proposedSize];
    NSRect rect = NSMakeRect(0, proposedSize.height - size.height, size.width, size.height);
    [self scrollview].frame = rect;
    
    rect.origin = NSZeroPoint;
    rect.size.width = _scrollview.contentSize.width;
    rect.size.height = [_delegate sessionViewDesiredHeightOfDocumentView];
    [_scrollview.documentView setFrame:rect];
}

- (void)setTitle:(NSString *)title {
    if (!title) {
        title = @"";
    }
    _title.title = title;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@:%p frame:%@ size:%@>", [self class], self,
            [NSValue valueWithRect:[self frame]], VT100GridSizeDescription([_delegate sessionViewGridSize])];
}

#pragma mark SessionTitleViewDelegate

- (BOOL)sessionTitleViewIsFirstResponder {
    return [_delegate sessionViewTerminalIsFirstResponder];
}

- (NSColor *)tabColor {
    return [_delegate sessionViewTabColor];
}

- (NSMenu *)menu {
    return [_delegate sessionViewContextMenu];
}

- (void)close {
    [_delegate sessionViewConfirmAndClose];
}

- (void)beginDrag {
    [_delegate sessionViewBeginDrag];
}

- (void)addAnnouncement:(iTermAnnouncementViewController *)announcement {
    [_announcements addObject:announcement];
    announcement.delegate = self;
    if (!_currentAnnouncement) {
        [self showNextAnnouncement];
    }
}

- (void)updateAnnouncementFrame {
    // Set the width
    NSRect rect = _currentAnnouncement.view.frame;
    rect.size.width = self.frame.size.width;
    _currentAnnouncement.view.frame = rect;
    
    // Make it change its height
    [(iTermAnnouncementView *)_currentAnnouncement.view sizeToFit];
    
    // Fix the origin
    rect = _currentAnnouncement.view.frame;
    rect.origin.y = self.frame.size.height - _currentAnnouncement.view.frame.size.height;
    _currentAnnouncement.view.frame = rect;
}

- (iTermAnnouncementViewController *)nextAnnouncement {
    iTermAnnouncementViewController *possibleAnnouncement = nil;
    while (_announcements.count) {
        possibleAnnouncement = [[_announcements[0] retain] autorelease];
        [_announcements removeObjectAtIndex:0];
        if (possibleAnnouncement.shouldBecomeVisible) {
            return possibleAnnouncement;
        }
    }
    return nil;
}

- (void)showNextAnnouncement {
    [_currentAnnouncement autorelease];
    _currentAnnouncement = nil;
    if (_announcements.count) {
        iTermAnnouncementViewController *possibleAnnouncement = [self nextAnnouncement];
        if (!possibleAnnouncement) {
            return;
        }
        _currentAnnouncement = [possibleAnnouncement retain];
        [self updateAnnouncementFrame];

        // Animate in
        NSRect finalRect = NSMakeRect(0,
                                      self.frame.size.height - _currentAnnouncement.view.frame.size.height,
                                      self.frame.size.width,
                                      _currentAnnouncement.view.frame.size.height);

        NSRect initialRect = finalRect;
        initialRect.origin.y += finalRect.size.height;
        _currentAnnouncement.view.frame = initialRect;

        [_currentAnnouncement.view.animator setFrame:finalRect];

        _currentAnnouncement.view.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [_currentAnnouncement didBecomeVisible];
        [self addSubview:_currentAnnouncement.view];
    }
}

#pragma mark - iTermAnnouncementDelegate

- (void)announcementWillDismiss:(iTermAnnouncementViewController *)announcement {
    [_announcements removeObject:announcement];
    if (announcement == _currentAnnouncement) {
        NSRect rect = announcement.view.frame;
        rect.origin.y += rect.size.height;
        [NSView animateWithDuration:0.25
                         animations:^{
                             [announcement.view.animator setFrame:rect];
                         }
                         completion:^(BOOL finished) {
                             [announcement.view removeFromSuperview];
                         }];

        if (!_inDealloc) {
            [self performSelector:@selector(showNextAnnouncement)
                       withObject:nil
                       afterDelay:[[NSAnimationContext currentContext] duration]];
        }
    }
}

@end
