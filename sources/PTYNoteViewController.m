//
//  PTYNoteViewController.m
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import "PTYNoteViewController.h"
#import "IntervalTree.h"
#import "NSView+iTerm.h"
#import "PTYNoteView.h"

static NSInteger gVisibleNotes;

NSString * const PTYNoteViewControllerShouldUpdatePosition = @"PTYNoteViewControllerShouldUpdatePosition";
NSString *const iTermAnnotationVisibilityDidChange = @"iTermAnnotationVisibilityDidChange";

static const CGFloat kBottomPadding = 3;

static void PTYNoteViewControllerIncrementVisibleCount(NSInteger delta) {
    gVisibleNotes += delta;
    if ((delta > 0 && gVisibleNotes == 1) ||
        (delta < 0 && gVisibleNotes == 0)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermAnnotationVisibilityDidChange object:nil];
    }
}

@interface PTYNoteViewController () <
    NSTextViewDelegate,
    PTYNoteViewDelegate>

@property(nonatomic, strong) NSTextView *textView;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, assign) BOOL watchForUpdate;
@end

@implementation PTYNoteViewController {
    NSTimeInterval highlightStartTime_;
    PTYNoteView *noteView_;
    NSTextView *textView_;
    NSScrollView *scrollView_;
    NSPoint anchor_;
    BOOL watchForUpdate_;
    BOOL hidden_;
}

@synthesize noteView = noteView_;
@synthesize textView = textView_;
@synthesize scrollView = scrollView_;
@synthesize anchor = anchor_;
@synthesize watchForUpdate = watchForUpdate_;

+ (BOOL)anyNoteVisible {
    return gVisibleNotes > 0;
}

- (instancetype)initWithAnnotation:(id<PTYAnnotationReading>)annotation {
    self = [super init];
    if (self) {
        _annotation = annotation;
        PTYNoteViewControllerIncrementVisibleCount(1);
        // NOTE: This must be the last thing done since it could cause a delegate method to be called.
        _annotation.delegate = self;
    }
    return self;
}

- (void)dealloc {
    if (!hidden_) {
        PTYNoteViewControllerIncrementVisibleCount(-1);
    }
    [noteView_ removeFromSuperview];
}

- (void)setNoteView:(PTYNoteView *)noteView {
    noteView_ = noteView;
    [self setView:noteView];
    [self updateTextViewString];
}

- (void)loadView {
    const CGFloat kWidth = 300;
    const CGFloat kHeight = 10;
    self.noteView = [[PTYNoteView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, kHeight)];
    self.noteView.autoresizesSubviews = YES;
    self.noteView.delegate = self;
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.5];
    shadow.shadowOffset = NSMakeSize(1, -1);
    shadow.shadowBlurRadius = 1.0;
    self.noteView.wantsLayer = YES;
    self.noteView.shadow = shadow;

    NSRect frame = NSMakeRect(0,
                              3,
                              kWidth,
                              kHeight);
    self.scrollView = [[NSScrollView alloc] initWithFrame:frame];
    scrollView_.scrollerStyle = NSScrollerStyleOverlay;
    scrollView_.drawsBackground = NO;
    scrollView_.hasVerticalScroller = YES;
    scrollView_.hasHorizontalScroller = NO;
    scrollView_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0,
                                                                  0,
                                                                  scrollView_.contentSize.width,
                                                                  scrollView_.contentSize.height)];
    textView_.allowsUndo = YES;
    textView_.minSize = scrollView_.frame.size;
    textView_.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    textView_.verticallyResizable = YES;
    textView_.horizontallyResizable = NO;
    textView_.autoresizingMask = NSViewWidthSizable;
    textView_.drawsBackground = NO;
    textView_.textContainer.containerSize = NSMakeSize(scrollView_.frame.size.width, FLT_MAX);
    textView_.textContainer.widthTracksTextView = YES;
    textView_.delegate = self;
    textView_.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    scrollView_.documentView = textView_;

    // Put the scrollview in a wrapper so we can have a few pixels of padding
    // at the bottom.
    NSRect wrapperFrame = scrollView_.frame;
    wrapperFrame.size.height += kBottomPadding;
    NSView *wrapper = [[NSView alloc] initWithFrame:wrapperFrame];
    wrapper.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    wrapper.autoresizesSubviews = YES;
    [wrapper addSubview:scrollView_];

    noteView_.contentView = wrapper;
    [self sizeToFit];
    [self updateTextViewString];
}

- (void)beginEditing {
    [[textView_ window] makeFirstResponder:textView_];
}

- (void)setAnchor:(NSPoint)anchor {
    anchor_ = anchor;

    NSRect superViewFrame = noteView_.superview.frame;
    CGFloat xOffset = 0;
    if (anchor_.x + noteView_.frame.size.width > superViewFrame.size.width) {
        xOffset = anchor_.x + noteView_.frame.size.width - superViewFrame.size.width;
    }
    noteView_.tipEdge = kPTYNoteViewTipEdgeTop;
    NSSize size = [noteView_ sizeThatFitsContentView];
    noteView_.point = NSMakePoint(xOffset, 0);
    noteView_.frame = NSMakeRect(anchor_.x - xOffset,
                                 anchor_.y,
                                 size.width,
                                 size.height);

    CGFloat superViewMaxY = superViewFrame.origin.y + superViewFrame.size.height;
    if (NSMaxY(noteView_.frame) > superViewMaxY) {
        noteView_.tipEdge = kPTYNoteViewTipEdgeBottom;
        noteView_.point = NSMakePoint(xOffset, noteView_.frame.size.height - 1);
        noteView_.frame = NSMakeRect(anchor_.x - xOffset,
                                     anchor_.y - noteView_.frame.size.height,
                                     size.width,
                                     size.height);
    }

    [noteView_ layoutSubviews];
}

- (void)checkForUpdate {
    [self setAnchor:anchor_];
}

- (void)setWatchForUpdate:(BOOL)watchForUpdate {
    if (watchForUpdate == watchForUpdate_) {
        return;
    }
    watchForUpdate_ = watchForUpdate;
    if (watchForUpdate) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(checkForUpdate)
                                                     name:PTYNoteViewControllerShouldUpdatePosition
                                                   object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

- (void)finalizeToggleOfHide:(BOOL)newValue {
    [noteView_ setHidden:newValue];
    noteView_.alphaValue = newValue ? 0 : 1;
    if (newValue) {
        PTYNoteViewControllerIncrementVisibleCount(-1);
    }
}

- (void)setNoteHidden:(BOOL)hidden {
    if (hidden == hidden_) {
        return;
    }
    hidden_ = hidden;
    [noteView_ setHidden:NO];
    [NSView animateWithDuration:0.25
                     animations:^{
                         [noteView_.animator setAlphaValue:(hidden ? 0 : 1)];
                     }
                     completion:^(BOOL finished) {
                         [self finalizeToggleOfHide:hidden];
                     }];
    if (!hidden) {
        PTYNoteViewControllerIncrementVisibleCount(1);
    }
    [self.delegate noteVisibilityDidChange:self];
}

- (BOOL)isEmpty {
    return [[textView_.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0;
}

- (void)updateTextViewString {
    [self view];  // Ensure textView exists.
    textView_.string = _annotation.stringValue;
}

- (BOOL)isNoteHidden {
    return hidden_;
}

- (void)noteViewPositionNeedsUpdate {
    self.anchor = anchor_;
}

- (void)noteViewMoveBy:(NSSize)distance {
    anchor_.x += distance.width;
    anchor_.y += distance.height;
    [self setAnchor:anchor_];
}

- (void)noteSetAnchor:(NSPoint)point {
    anchor_ = point;
}

- (NSSize)textViewFittingSize {
    [self view];
    NSLayoutManager *layoutManager = textView_.layoutManager;
    NSTextContainer *textContainer = textView_.textContainer;
    [layoutManager ensureLayoutForTextContainer:textContainer];
    NSRect usedRect = [layoutManager usedRectForTextContainer:textContainer];

    const CGFloat kMinTextViewWidth = 250;
    usedRect.size.width = MAX(usedRect.size.width, kMinTextViewWidth);
    return usedRect.size;
}

- (NSSize)fittingSize {
    return [self sizeForTextViewSize:[self textViewFittingSize]];
}

- (NSSize)sizeForTextViewSize:(NSSize)textViewSize {
    NSSize size = [NSScrollView frameSizeForContentSize:textViewSize
                                horizontalScrollerClass:[[scrollView_ horizontalScroller] class]
                                  verticalScrollerClass:[[scrollView_ verticalScroller] class]
                                             borderType:NSNoBorder
                                            controlSize:NSControlSizeRegular
                                          scrollerStyle:[scrollView_ scrollerStyle]];
    size.height += kBottomPadding;
    return size;
}

- (void)sizeToFit {
    const NSSize textViewFittingSize = [self textViewFittingSize];
    const NSSize scrollViewSize = [self sizeForTextViewSize:textViewFittingSize];
    NSRect theFrame = NSMakeRect(NSMinX(scrollView_.frame),
                                 NSMinY(scrollView_.frame),
                                 scrollViewSize.width,
                                 scrollViewSize.height);

    NSView *wrapper = scrollView_.superview;
    wrapper.frame = theFrame;

    textView_.minSize = textViewFittingSize;
    textView_.frame = NSMakeRect(0, 0, textViewFittingSize.width, textViewFittingSize.height);

    [self setAnchor:anchor_];
}

- (void)makeFirstResponder {
    [self.view.window makeFirstResponder:textView_];
}

#pragma mark - PTYNoteViewDelegate

- (PTYNoteViewController *)noteViewController {
    return self;
}

- (void)killNote {
    [self.delegate noteDidRequestRemoval:self];
}

#pragma mark - NSControlTextEditingDelegate

- (void)textDidChange:(NSNotification *)notification {
    [self.delegate note:self setAnnotation:_annotation stringValue:textView_.string];
    if (!noteView_.heightChangedManually) {
        const NSSize fittingSize = [self fittingSize];
        if (fittingSize.height > scrollView_.superview.frame.size.height) {
            [self sizeToFit];
        }
    }
}

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector {
    if (aSelector == @selector(cancelOperation:)) {
        [self.delegate note:self setAnnotation:_annotation stringValue:textView_.string];
        [self.delegate noteDidEndEditing:self];
        return YES;
    }
    return NO;
}

- (void)updateBackgroundColor {
    if (self.noteView.superview == nil) {
        self.noteView.backgroundColor = [self.noteView defaultBackgroundColor];
        return;
    }
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - highlightStartTime_;
    const NSTimeInterval duration = 0.75;
    // Alpha counts from 0 to 1.
    float alpha = 1.0 - MIN(MAX(0, (duration - elapsed) / duration), 1);

    // Square alpha so it spends more time in the highlighted end of the range.
    alpha = alpha * alpha;

    NSColor *defaultBg = [self.noteView defaultBackgroundColor];
    CGFloat highlightComponents[] = { 0.9, 0.8, 0 };
    CGFloat components[3] = {
        [defaultBg redComponent] * alpha + (1 - alpha) * highlightComponents[0],
        [defaultBg greenComponent] * alpha + (1 - alpha) * highlightComponents[1],
        [defaultBg blueComponent] * alpha + (1 - alpha) * highlightComponents[2]
    };
    self.noteView.backgroundColor = [NSColor colorWithCalibratedRed:components[0] green:components[1] blue:components[2] alpha:1];
    [self.noteView setNeedsDisplay:YES];
    if (alpha < 1) {
        [self performSelector:@selector(updateBackgroundColor) withObject:nil afterDelay:1/30.0];
    }
}

- (void)highlight {
    highlightStartTime_ = [NSDate timeIntervalSinceReferenceDate];
    [self performSelector:@selector(updateBackgroundColor) withObject:nil afterDelay:1/30.0];
    [self.noteView setNeedsDisplay:YES];
}

#pragma mark - PTYAnnotationDelegate

- (void)annotationDidRequestHide:(id<PTYAnnotationReading>)annotation {
    [self setNoteHidden:YES];
}

- (void)annotationStringDidChange:(id<PTYAnnotationReading>)annotation {
    [self updateTextViewString];
}

- (void)annotationWillBeRemoved:(id<PTYAnnotationReading>)annotation {
    [self.delegate noteWillBeRemoved:self];
}

@end
