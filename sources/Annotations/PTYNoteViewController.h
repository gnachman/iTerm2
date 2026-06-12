//
//  PTYNoteViewController.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>
#import "PTYAnnotation.h"
#import "PTYNoteView.h"

// Post this when the note view's anchor has a chance to become centered.
extern NSString * const PTYNoteViewControllerShouldUpdatePosition;

// Notification posted when we transition between [any note is visible] <-> [no notes are visible]
extern NSString *const iTermAnnotationVisibilityDidChange;

@class PTYNoteViewController;

@protocol PTYNoteViewControllerDelegate <NSObject>
- (void)noteDidRequestRemoval:(PTYNoteViewController *)note;
- (void)noteWillBeRemoved:(PTYNoteViewController *)note;
- (void)noteDidEndEditing:(PTYNoteViewController *)note;
- (void)noteVisibilityDidChange:(PTYNoteViewController *)note;
- (void)note:(PTYNoteViewController *)note
setAnnotation:(id<PTYAnnotationReading>)annotation
 stringValue:(NSString *)stringValue;
@end

@interface PTYNoteViewController : NSViewController<PTYAnnotationDelegate>

@property(nonatomic, weak) id<PTYNoteViewControllerDelegate> delegate;
@property(nonatomic, strong) id<PTYAnnotationReading> annotation;
@property(nonatomic, strong) PTYNoteView *noteView;
@property(nonatomic, assign) NSPoint anchor;

+ (BOOL)anyNoteVisible;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAnnotation:(id<PTYAnnotationReading>)annotation;

- (void)beginEditing;
- (BOOL)isEmpty;
- (void)setNoteHidden:(BOOL)hidden;
- (BOOL)isNoteHidden;
- (void)sizeToFit;
- (void)makeFirstResponder;
- (void)highlight;

@end
