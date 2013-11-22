//
//  PTYNoteViewController.m
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import "PTYNoteViewController.h"
#import "PTYNoteView.h"

NSString * const PTYNoteViewControllerShouldUpdatePosition = @"PTYNoteViewControllerShouldUpdatePosition";

static const CGFloat kLeftMargin = 15;
static const CGFloat kRightMargin = 10;
static const CGFloat kTopMargin = 10;
static const CGFloat kBottomMargin = 5;

@interface PTYNoteViewController ()
@property(nonatomic, retain) NSTextView *textView;
@property(nonatomic, retain) NSScrollView *scrollView;
@property(nonatomic, assign) BOOL watchForUpdate;
@end

@implementation PTYNoteViewController

@synthesize noteView = noteView_;
@synthesize textView = textView_;
@synthesize scrollView = scrollView_;
@synthesize anchor = anchor_;
@synthesize watchForUpdate = watchForUpdate_;
@synthesize isInLineBuffer = isInLineBuffer_;
@synthesize absolutePosition = absolutePosition_;
@synthesize absoluteLineNumber = absoluteLineNumber_;

- (void)dealloc {
    [noteView_ removeFromSuperview];
    noteView_.noteViewController = nil;
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
    const CGFloat kHeight = 30;
    self.noteView = [[[PTYNoteView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, kHeight)] autorelease];
    self.noteView.noteViewController = self;
    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    shadow.shadowColor = [NSColor blackColor];
    shadow.shadowOffset = NSMakeSize(1, -1);
    shadow.shadowBlurRadius = 1.0;
    self.noteView.wantsLayer = YES;
    self.noteView.shadow = shadow;

    NSSize size = NSMakeSize(kWidth - kLeftMargin - kRightMargin,
                             kHeight - kTopMargin - kBottomMargin);
    NSRect frame = NSMakeRect(kLeftMargin,
                              kTopMargin,
                              size.width,
                              size.height);
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
    textView_.minSize = size;
    textView_.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    textView_.verticallyResizable = YES;
    textView_.horizontallyResizable = NO;
    textView_.autoresizingMask = NSViewWidthSizable;
    textView_.drawsBackground = NO;
    textView_.textContainer.containerSize = NSMakeSize(size.width, FLT_MAX);
    textView_.textContainer.widthTracksTextView = YES;

    scrollView_.documentView = textView_;

    [noteView_ addSubview:scrollView_];
}

- (void)beginEditing {
    [[textView_ window] makeFirstResponder:textView_];
}

- (void)setAnchor:(NSPoint)anchor {
    anchor_ = anchor;

    NSRect superViewFrame = noteView_.superview.frame;
    CGFloat superViewMaxY = superViewFrame.origin.y + superViewFrame.size.height;

    CGFloat height = noteView_.frame.size.height;
    CGFloat visibleHeight = noteView_.visibleFrame.size.height;
    CGFloat shadowHeight = height - visibleHeight;

    if (anchor_.y - visibleHeight / 2 < 0) {
        // Can't center the anchor because some of the note would be off the top of the view.
        noteView_.frame = NSMakeRect(anchor_.x,
                                     0,
                                     noteView_.frame.size.width,
                                     noteView_.frame.size.height);
        noteView_.point = NSMakePoint(0, anchor_.y);
        self.watchForUpdate = NO;
    } else if (anchor_.y + visibleHeight / 2 + shadowHeight > superViewMaxY) {
        // Can't center the anchor because some of the note would be off the bottom of the view.
        const CGFloat shift = (superViewMaxY - height) - (anchor_.y - visibleHeight / 2);
        noteView_.frame = NSMakeRect(anchor_.x,
                                     superViewMaxY - height,
                                     noteView_.frame.size.width,
                                     noteView_.frame.size.height);
        noteView_.point = NSMakePoint(0, visibleHeight / 2 - shift);
        self.watchForUpdate = YES;
    } else {
        // Center the anchor
        noteView_.frame = NSMakeRect(anchor_.x,
                                     anchor_.y - visibleHeight / 2,
                                     noteView_.frame.size.width,
                                     noteView_.frame.size.height);
        noteView_.point = NSMakePoint(0, visibleHeight / 2);
        self.watchForUpdate = NO;
    }
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
    noteView_.animator.alphaValue = hidden ? 0 : 1;
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

    NSSize scrollViewSize = [NSScrollView frameSizeForContentSize:usedRect.size
                                          horizontalScrollerClass:[[scrollView_ horizontalScroller] class]
                                            verticalScrollerClass:[[scrollView_ verticalScroller] class]
                                                       borderType:NSNoBorder
                                                      controlSize:NSRegularControlSize
                                                    scrollerStyle:[scrollView_ scrollerStyle]];
    noteView_.frame = NSMakeRect(0,
                                 0,
                                 kLeftMargin + kRightMargin + scrollViewSize.width,
                                 kTopMargin + kBottomMargin + scrollViewSize.height);
    
    scrollView_.frame = NSMakeRect(kLeftMargin, kTopMargin, scrollViewSize.width, scrollViewSize.height);

    textView_.minSize = usedRect.size;
    textView_.frame = NSMakeRect(0, 0, usedRect.size.width, usedRect.size.height);
    
    [self setAnchor:anchor_];
}

@end
