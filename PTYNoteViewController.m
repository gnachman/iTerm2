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
@property(nonatomic, retain) NSTextField *textField;
@end

@implementation PTYNoteViewController

@synthesize noteView = noteView_;
@synthesize textField = textField_;

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
    
    const CGFloat kLeftMargin = 15;
    const CGFloat kRightMargin = 10;
    const CGFloat kTopMargin = 10;
    const CGFloat kBottomMargin = 5;
    self.textField = [[[NSTextField alloc] initWithFrame:NSMakeRect(kLeftMargin,
                                                                    kTopMargin,
                                                                    kWidth - kLeftMargin - kRightMargin,
                                                                    kHeight - kTopMargin - kBottomMargin)] autorelease];
    [textField_ setStringValue:@""];
    [textField_ setBezeled:NO];
    [textField_ setEditable:YES];
    [textField_ setDrawsBackground:NO];
    [textField_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    NSTextFieldCell *cell = textField_.cell;
    cell.placeholderString = @"Enter note here";
    [noteView_ addSubview:textField_];
}

- (void)beginEditing {
    [[textField_ window] makeFirstResponder:textField_];
}

@end
