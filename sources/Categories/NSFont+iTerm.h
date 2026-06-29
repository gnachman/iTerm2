//
//  NSFont+iTerm.h
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSFont (iTerm)

// Encoded font name, suitable for storing in a profile.
@property(nonatomic, readonly) NSString *stringValue;
@property(nonatomic, readonly) int it_metalFontID;
- (NSFont *)it_fontByAddingToPointSize:(CGFloat)delta;
+ (NSFont *)it_toolbeltFont;
- (BOOL)it_hasStylisticAlternatives;
- (BOOL)it_hasContextualAlternates;
- (CGSize)it_pitch;

+ (instancetype _Nullable)it_fontWithMetalID:(int)metalID;

@end

NS_ASSUME_NONNULL_END
