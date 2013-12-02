//
//  PTYNoteView.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>

@class PTYNoteViewController;

@interface PTYNoteView : NSView {
    PTYNoteViewController *noteViewController_;  // weak
    BOOL dragRight_;
    BOOL dragBottom_;
    NSPoint dragOrigin_;
    NSSize originalSize_;
    NSPoint point_;
    NSView *contentView_;
}

@property(nonatomic, assign) PTYNoteViewController *noteViewController;

// Location of arrow relative to top-left corner of this view.
@property(nonatomic, assign) NSPoint point;
@property(nonatomic, retain) NSView *contentView;

- (NSColor *)backgroundColor;

@end
