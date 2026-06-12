//
//  iTermGenericStatusBarContainer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

#import "iTermStatusBarViewController.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermGenericStatusBarContainer<NSObject>
- (NSColor *)genericStatusBarContainerBackgroundColor;
@end

@interface iTermGenericStatusBarContainer : NSView<iTermStatusBarContainer>
@property (nonatomic, weak) id<iTermGenericStatusBarContainer> delegate;
@end

NS_ASSUME_NONNULL_END
