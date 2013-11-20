//
//  PTYNoteViewController.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>
#import "PTYNoteView.h"

// Post this when the note view's anchor has a chance to become centered.
extern NSString * const PTYNoteViewControllerShouldUpdatePosition;

@interface PTYNoteViewController : NSViewController <PTYNoteViewDelegate> {
    PTYNoteView *noteView_;
    NSTextView *textView_;
    NSPoint anchor_;
    BOOL watchForUpdate_;
}

@property(nonatomic, retain) PTYNoteView *noteView;
@property(nonatomic, assign) NSPoint anchor;

- (void)beginEditing;

@end
