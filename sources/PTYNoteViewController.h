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

@class PTYNoteViewController;

@protocol PTYNoteViewControllerDelegate <NSObject>
- (void)noteDidRequestRemoval:(PTYNoteViewController *)note;
- (void)noteDidEndEditing:(PTYNoteViewController *)note;
@end

@interface PTYNoteViewController : NSViewController <
  IntervalTreeObject,
  NSTextViewDelegate,
  PTYNoteViewDelegate> {
    PTYNoteView *noteView_;
    NSTextView *textView_;
    NSScrollView *scrollView_;
    NSPoint anchor_;
    BOOL watchForUpdate_;
    BOOL hidden_;
}

@property(nonatomic, retain) PTYNoteView *noteView;
@property(nonatomic, assign) NSPoint anchor;
@property(nonatomic, assign) id<PTYNoteViewControllerDelegate> delegate;

- (void)beginEditing;
- (BOOL)isEmpty;
- (void)setString:(NSString *)string;
- (void)setNoteHidden:(BOOL)hidden;
- (BOOL)isNoteHidden;
- (void)sizeToFit;
- (void)makeFirstResponder;
- (void)highlight;

@end
