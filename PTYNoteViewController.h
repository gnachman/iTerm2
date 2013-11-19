//
//  PTYNoteViewController.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>
#import "PTYNoteView.h"

@interface PTYNoteViewController : NSViewController <PTYNoteViewDelegate> {
    PTYNoteView *noteView_;
    NSTextField *textField_;
}

@property(nonatomic, retain) PTYNoteView *noteView;

- (void)beginEditing;

@end
