//
//  HighlightTrigger.h
//  iTerm2
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "Trigger.h"

// Dictionary keys for -highlightTextInRange:basedAtAbsoluteLineNumber:absoluteLineNumber:color:
extern NSString * const kHighlightForegroundColor;
extern NSString * const kHighlightBackgroundColor;

@protocol iTermColorSettable<NSObject>
- (void)setTextColor:(NSColor *)textColor;
- (void)setBackgroundColor:(NSColor *)backgroundColor;
@end

@interface HighlightTrigger : Trigger<iTermColorSettable>

+ (NSString *)title;

@end
