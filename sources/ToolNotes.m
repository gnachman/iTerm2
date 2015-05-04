//
//  ToolNotes.m
//  iTerm
//
//  Created by George Nachman on 9/19/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolNotes.h"
#import "NSFileManager+iTerm.h"

static NSString *kToolNotesSetTextNotification = @"kToolNotesSetTextNotification";

@interface ToolNotes ()
- (NSString *)filename;
@end

@implementation ToolNotes {
    NSTextView *textView_;
    NSFileManager *filemanager_;
    BOOL ignoreNotification_;
    NSScrollView *_scrollview;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        filemanager_ = [[NSFileManager alloc] init];

        _scrollview = [[[NSScrollView alloc]
                        initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)] autorelease];
        _scrollview.contentView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollview.translatesAutoresizingMaskIntoConstraints = NO;
        [_scrollview setBorderType:NSBezelBorder];
        [_scrollview setHasVerticalScroller:YES];
        [_scrollview setHasHorizontalScroller:NO];
        _scrollview.verticalScroller.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollview.horizontalScroller.translatesAutoresizingMaskIntoConstraints = NO;

        NSSize contentSize = [_scrollview contentSize];
        textView_ = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        textView_.translatesAutoresizingMaskIntoConstraints = NO;
        [textView_ setAllowsUndo:YES];
        [textView_ setMinSize:NSMakeSize(0.0, contentSize.height)];
        [textView_ setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
        [textView_ setVerticallyResizable:YES];
        [textView_ setHorizontallyResizable:NO];

        [[textView_ textContainer] setContainerSize:NSMakeSize(contentSize.width, FLT_MAX)];
        [[textView_ textContainer] setWidthTracksTextView:YES];
        [textView_ setDelegate:self];
        [textView_ readRTFDFromFile:[self filename]];
        [_scrollview setDocumentView:textView_];
                
        [self addSubview:_scrollview];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setText:)
                                                     name:kToolNotesSetTextNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [textView_ writeRTFDToFile:[self filename] atomically:NO];
    [filemanager_ release];
    [super dealloc];
}

- (NSString *)filename
{
    return [NSString stringWithFormat:@"%@/notes.rtfd", [filemanager_ applicationSupportDirectory]];
}
         
- (void)textDidChange:(NSNotification *)aNotification
{
    // Avoid saving huge files because of the slowdown it would cause.
    if ([[textView_ textStorage] length] < 100 * 1024) {
        [textView_ writeRTFDToFile:[self filename] atomically:NO];
        ignoreNotification_ = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:kToolNotesSetTextNotification
                                                            object:nil];
        ignoreNotification_ = NO;
    }
    [textView_ breakUndoCoalescing];
}

- (void)setText:(NSNotification *)aNotification
{
    if (!ignoreNotification_) {
        [textView_ readRTFDFromFile:[self filename]];
    }
}

- (void)shutdown {
}

- (CGFloat)minimumHeight
{
    return 15;
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    NSRect frame = self.frame;
    _scrollview.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    NSSize contentSize = [_scrollview contentSize];
    textView_.frame = NSMakeRect(0, 0, contentSize.width, contentSize.height);
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSRect frame = self.frame;
    _scrollview.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    NSSize contentSize = [_scrollview contentSize];
    textView_.frame = NSMakeRect(0, 0, contentSize.width, contentSize.height);
}

@end
