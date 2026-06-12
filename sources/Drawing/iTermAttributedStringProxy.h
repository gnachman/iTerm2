//
//  iTermAttributedStringProxy.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/16/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Wraps an attributed string that has the same attributes throughout. Provides faster equality
// and hashing than NSAttributedString, which is horrifically slow. Ignores all attributes that
// aren't needed by iTermTextDrawingHelper. If you aren't iTermTextDrawingHelper using this to
// cache CTLineRefs then you probably shouldn't use this.
@interface iTermAttributedStringProxy : NSObject<NSCopying>

+ (instancetype)withAttributedString:(NSAttributedString *)attributedString;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
