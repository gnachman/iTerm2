//
//  NSBezierPath+iTerm.h
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSBezierPath (iTerm)

+ (NSBezierPath *)smoothPathAroundBottomOfFrame:(NSRect)frame;
- (CGPathRef)iterm_CGPath CF_RETURNS_NOT_RETAINED;
- (CGPathRef)iterm_openCGPath CF_RETURNS_NOT_RETAINED;

@end

NS_ASSUME_NONNULL_END

