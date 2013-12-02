//
//  PTYNoteViewController.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>
#import "IntervalTree.h"
#import "PTYNoteView.h"

// Post this when the note view's anchor has a chance to become centered.
extern NSString * const PTYNoteViewControllerShouldUpdatePosition;

@protocol PTYNoteViewControllerDelegate
@end

@interface PTYNoteViewController : NSViewController  <IntervalTreeObject> {
    PTYNoteView *noteView_;
    NSTextView *textView_;
    NSScrollView *scrollView_;
    NSPoint anchor_;
    BOOL watchForUpdate_;
    BOOL hidden_;
}

@property(nonatomic, retain) PTYNoteView *noteView;
@property(nonatomic, assign) NSPoint anchor;

- (void)beginEditing;
- (BOOL)isEmpty;
- (void)setString:(NSString *)string;
- (void)setNoteHidden:(BOOL)hidden;
- (BOOL)isNoteHidden;
- (void)sizeToFit;

@end
