//
//  PTYNoteViewController.m
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import "PTYNoteViewController.h"
#import "IntervalTree.h"
#import "PTYNoteView.h"

static NSString *const kNoteViewTextKey = @"Text";

NSString * const PTYNoteViewControllerShouldUpdatePosition = @"PTYNoteViewControllerShouldUpdatePosition";

static const CGFloat kBottomPadding = 3;

@interface PTYNoteViewController ()
@property(nonatomic, retain) NSTextView *textView;
@property(nonatomic, retain) NSScrollView *scrollView;
@property(nonatomic, assign) BOOL watchForUpdate;
@end

@implementation PTYNoteViewController {
    NSTimeInterval highlightStartTime_;
}

@synthesize noteView = noteView_;
@synthesize textView = textView_;
@synthesize scrollView = scrollView_;
@synthesize anchor = anchor_;
@synthesize watchForUpdate = watchForUpdate_;
@synthesize entry;
@synthesize delegate;

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        self.string = dict[kNoteViewTextKey];
    }
    return self;
}

- (void)dealloc {
    [noteView_ removeFromSuperview];
    noteView_.delegate = nil;
    [noteView_ release];
    [textView_ release];
    [scrollView_ release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)setNoteView:(PTYNoteView *)noteView {
    [noteView_ autorelease];
    noteView_ = [noteView retain];
    [self setView:noteView];
}

- (void)loadView {
    const CGFloat kWidth = 300;
    const CGFloat kHeight = 10;
    self.noteView = [[[PTYNoteView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, kHeight)] autorelease];
    self.noteView.autoresizesSubviews = YES;
    self.noteView.delegate = self;
    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.5];
    shadow.shadowOffset = NSMakeSize(1, -1);
    shadow.shadowBlurRadius = 1.0;
    self.noteView.wantsLayer = YES;
    self.noteView.shadow = shadow;

    NSRect frame = NSMakeRect(0,
                              3,
                              kWidth,
                              kHeight);
    self.scrollView = [[[NSScrollView alloc] initWithFrame:frame] autorelease];
    scrollView_.drawsBackground = NO;
    scrollView_.hasVerticalScroller = YES;
    scrollView_.hasHorizontalScroller = NO;
    scrollView_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.textView = [[[NSTextView alloc] initWithFrame:NSMakeRect(0,
                                                                  0,
                                                                  scrollView_.contentSize.width,
                                                                  scrollView_.contentSize.height)]
                     autorelease];
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
    scrollView_.documentView = textView_;

    // Put the scrollview in a wrapper so we can have a few pixels of padding
    // at the bottom.
    NSRect wrapperFrame = scrollView_.frame;
    wrapperFrame.size.height += kBottomPadding;
    NSView *wrapper = [[[NSView alloc] initWithFrame:wrapperFrame] autorelease];
    wrapper.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    wrapper.autoresizesSubviews = YES;
    [wrapper addSubview:scrollView_];

    noteView_.contentView = wrapper;
    [self sizeToFit];
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

- (void)finalizeToggleOfHide {
    [noteView_ setHidden:hidden_];
    noteView_.alphaValue = hidden_ ? 0 : 1;
}

- (void)setNoteHidden:(BOOL)hidden {
    if (hidden == hidden_) {
        return;
    }
    hidden_ = hidden;
    [noteView_ setHidden:NO];
    [noteView_.animator setAlphaValue:(hidden ? 0 : 1)];
    [self performSelector:@selector(finalizeToggleOfHide)
               withObject:nil
               afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (BOOL)isEmpty {
    return [[textView_.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0;
}

- (void)setString:(NSString *)string {
    [self view];  // Ensure textView exists.
    textView_.string = string;
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

- (void)sizeToFit {
    NSLayoutManager *layoutManager = textView_.layoutManager;
    NSTextContainer *textContainer = textView_.textContainer;
    [layoutManager ensureLayoutForTextContainer:textContainer];
    NSRect usedRect = [layoutManager usedRectForTextContainer:textContainer];

    const CGFloat kMinTextViewWidth = 250;
    usedRect.size.width = MAX(usedRect.size.width, kMinTextViewWidth);

    NSSize scrollViewSize = [NSScrollView frameSizeForContentSize:usedRect.size
                                          horizontalScrollerClass:[[scrollView_ horizontalScroller] class]
                                            verticalScrollerClass:[[scrollView_ verticalScroller] class]
                                                       borderType:NSNoBorder
                                                      controlSize:NSRegularControlSize
                                                    scrollerStyle:[scrollView_ scrollerStyle]];
    NSRect theFrame = NSMakeRect(NSMinX(scrollView_.frame),
                                 NSMinY(scrollView_.frame),
                                 scrollViewSize.width,
                                 scrollViewSize.height);

    NSView *wrapper = scrollView_.superview;
    theFrame.size.height += kBottomPadding;
    wrapper.frame = theFrame;

    textView_.minSize = usedRect.size;
    textView_.frame = NSMakeRect(0, 0, usedRect.size.width, usedRect.size.height);

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

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector {
    if (aSelector == @selector(cancelOperation:)) {
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

#pragma mark - IntervalTreeObject

- (NSDictionary *)dictionaryValue {
    return @{ kNoteViewTextKey: textView_.string ?: @"" };
}

@end
