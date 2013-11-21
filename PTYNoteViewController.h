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

@protocol PTYNoteViewControllerDelegate
@end

@interface PTYNoteViewController : NSViewController {
    PTYNoteView *noteView_;
    NSTextView *textView_;
    NSPoint anchor_;
    BOOL watchForUpdate_;
    BOOL hidden_;
    long long absLine_;
}

@property(nonatomic, retain) PTYNoteView *noteView;
@property(nonatomic, assign) NSPoint anchor;
@property(nonatomic, assign) long long absLine;

- (void)beginEditing;
- (BOOL)isEmpty;
- (void)setString:(NSString *)string;
- (void)setNoteHidden:(BOOL)hidden;
- (BOOL)isNoteHidden;

@end
