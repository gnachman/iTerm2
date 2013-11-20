//
//  PTYNoteView.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>

@protocol PTYNoteViewDelegate <NSObject>
@end

@interface PTYNoteView : NSView {
    id<PTYNoteViewDelegate> delegate_;
    BOOL dragRight_;
    BOOL dragBottom_;
    NSPoint dragOrigin_;
    NSSize originalSize_;
    NSPoint point_;
}

@property(nonatomic, assign) id<PTYNoteViewDelegate> delegate;

// Location of arrow relative to top-left corner of this view.
@property(nonatomic, assign) NSPoint point;

- (NSColor *)backgroundColor;
- (NSRect)visibleFrame;

@end
