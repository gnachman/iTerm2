//
//  iTermKeystrokeFormatter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermKeystroke;

@interface iTermKeystrokeFormatter : NSObject

// Returns a human-readable representation of a keystroke (e.g., ^X)
// Formats the key combination using the current keyboard's mapping from
// keycode to character. If virtualkeyCode is 0, it will fall back to the
// character embedded in the keystroke.
+ (NSString *)stringForKeystroke:(iTermKeystroke *)keystroke;

@end

NS_ASSUME_NONNULL_END
