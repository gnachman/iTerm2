//
//  NSColor+PSM.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/24/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSColor (PSM)

- (NSColor *)it_srgbForColorInWindow:(NSWindow *)window;
- (CGFloat)it_hspBrightness;

@end

NS_ASSUME_NONNULL_END
