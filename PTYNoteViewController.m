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

@interface PTYNoteViewController ()
@property(nonatomic, retain) NSTextView *textView;
@property(nonatomic, assign) BOOL watchForUpdate;
@end

@implementation PTYNoteViewController

@synthesize noteView = noteView_;
@synthesize textView = textView_;
@synthesize anchor = anchor_;
@synthesize watchForUpdate = watchForUpdate_;
@synthesize hidden = hidden_;

- (void)dealloc {
    [noteView_ removeFromSuperview];
    [noteView_ release];
    [textView_ release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)setNoteView:(PTYNoteView *)noteView {
    [noteView_ autorelease];
    noteView_ = [noteView retain];
    [self setView:noteView];
}

- (void)loadView {
    [super loadView];
    const CGFloat kWidth = 300;
    const CGFloat kHeight = 50;
    self.noteView = [[[PTYNoteView alloc] initWithFrame:NSMakeRect(0, 0, kWidth, kHeight)] autorelease];
    self.noteView.delegate = self;
    NSShadow *shadow = [[[NSShadow alloc] init] autorelease];
    shadow.shadowColor = [NSColor blackColor];
    shadow.shadowOffset = NSMakeSize(1, -1);
    shadow.shadowBlurRadius = 1.0;
    self.noteView.wantsLayer = YES;
    self.noteView.shadow = shadow;


    const CGFloat kLeftMargin = 15;
    const CGFloat kRightMargin = 10;
    const CGFloat kTopMargin = 10;
    const CGFloat kBottomMargin = 5;

    NSSize size = NSMakeSize(kWidth - kLeftMargin - kRightMargin,
                             kHeight - kTopMargin - kBottomMargin);
    NSRect frame = NSMakeRect(kLeftMargin,
                              kTopMargin,
                              size.width,
                              size.height);
    NSScrollView *scrollview = [[[NSScrollView alloc]
                                 initWithFrame:frame] autorelease];
    scrollview.drawsBackground = NO;
    scrollview.hasVerticalScroller = YES;
    scrollview.hasHorizontalScroller = NO;
    scrollview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.textView = [[[NSTextView alloc] initWithFrame:frame] autorelease];
    textView_.allowsUndo = YES;
    textView_.minSize = size;
    textView_.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    textView_.verticallyResizable = YES;
    textView_.horizontallyResizable = NO;
    textView_.autoresizingMask = NSViewWidthSizable;
    textView_.drawsBackground = NO;
    textView_.textContainer.containerSize = NSMakeSize(size.width, FLT_MAX);
    textView_.textContainer.widthTracksTextView = YES;

    scrollview.documentView = textView_;

    [noteView_ addSubview:scrollview];
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

@end
