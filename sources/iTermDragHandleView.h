//
//  iTermDragHandleView.h
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import <Cocoa/Cocoa.h>

@class iTermDragHandleView;

@protocol iTermDragHandleViewDelegate <NSObject>

// Should return the number of pixels right (or left, for negative values) the drag handle was
// allowed to move.
- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta;

@optional

// Called when dragging finishes.
- (void)dragHandleViewDidFinishMoving:(iTermDragHandleView *)dragHandle;

@end

// An invisible vertical drag handle that reports horizontal drags to the delegate.
@interface iTermDragHandleView : NSView

@property(nonatomic, assign) id<iTermDragHandleViewDelegate> delegate;

@end
