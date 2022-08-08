//
//  NSFont+iTerm.h
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSFont (iTerm)

// Encoded font name, suitable for storing in a profile.
@property(nonatomic, readonly) NSString *stringValue;
- (NSFont *)it_fontByAddingToPointSize:(CGFloat)delta;
+ (NSFont *)it_toolbeltFont;
- (BOOL)it_hasStylisticAlternatives;

@end
