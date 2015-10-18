//
//  PTYNoteView.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>

@class PTYNoteViewController;

typedef NS_ENUM(NSInteger, PTYNoteViewTipEdge) {
    kPTYNoteViewTipEdgeLeft,
    kPTYNoteViewTipEdgeTop,
    kPTYNoteViewTipEdgeRight,
    kPTYNoteViewTipEdgeBottom
};

@protocol PTYNoteViewDelegate <NSObject>
- (PTYNoteViewController *)noteViewController;
- (void)killNote;
@end

@interface PTYNoteView : NSView {
    PTYNoteViewController *noteViewController_;  // weak
    BOOL dragRight_;
    BOOL dragBottom_;
    NSPoint dragOrigin_;
    NSSize originalSize_;
    NSPoint point_;
    NSView *contentView_;
    PTYNoteViewTipEdge tipEdge_;
    id<PTYNoteViewDelegate> delegate_;
    NSButton *killButton_;
    NSColor *backgroundColor_;
}

@property(nonatomic, assign) id<PTYNoteViewDelegate> delegate;

// Location of arrow relative to top-left corner of this view.
@property(nonatomic, assign) NSPoint point;
@property(nonatomic, retain) NSView *contentView;
@property(nonatomic, assign) PTYNoteViewTipEdge tipEdge;
@property(nonatomic, retain) NSColor *backgroundColor;

- (NSColor *)defaultBackgroundColor;
- (void)layoutSubviews;
- (NSSize)sizeThatFitsContentView;

@end
