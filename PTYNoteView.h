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
    BOOL dragHorizontal_;
    BOOL dragBottom_;
    NSPoint dragOrigin_;
    NSSize originalSize_;
}

@property(nonatomic, assign) id<PTYNoteViewDelegate> delegate;

- (NSColor *)backgroundColor;

@end
