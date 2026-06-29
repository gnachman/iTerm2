//
//  iTermOptionallyBordered.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/21.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermOptionallyBordered
- (void)setOptionalBorderEnabled:(BOOL)enabled;
@end

@interface NSTextField(OptionallyBordered)<iTermOptionallyBordered>
@end

NS_ASSUME_NONNULL_END
