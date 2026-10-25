//
//  iTermGenericStatusBarContainer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermStatusBarViewController.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PaneFocusFollowsMousePane;

@protocol iTermGenericStatusBarContainer<NSObject>
- (NSColor *)genericStatusBarContainerBackgroundColor;
// The pane the status bar belongs to, for focus follows mouse.
- (nullable id<PaneFocusFollowsMousePane>)genericStatusBarContainerFocusFollowsMousePane;
@end

@interface iTermGenericStatusBarContainer : NSView<iTermStatusBarContainer>
@property (nonatomic, weak) id<iTermGenericStatusBarContainer> delegate;
@end

NS_ASSUME_NONNULL_END
