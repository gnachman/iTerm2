//
//  NSColor+PSM.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/24/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSColor (PSM)

- (NSColor *)it_srgbForColorInWindow:(NSWindow * _Nullable)window;
- (CGFloat)it_hspBrightness;

// White or black, whichever contrasts with the receiver used as a background
// (e.g. a tab-group name drawn on the group's color). One shared threshold so
// every renderer of the same background picks the same text color.
- (NSColor *)psmContrastingTextColor;

@end

NS_ASSUME_NONNULL_END
