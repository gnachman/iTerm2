//
//  PTYNoteViewController.m
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import "PTYNoteViewController.h"
#import "PTYNoteView.h"

@interface PTYNoteViewController ()
@property(nonatomic, retain) NSTextView *textView;
@end

@implementation PTYNoteViewController

@synthesize noteView = noteView_;
@synthesize textView = textView_;

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

@end
