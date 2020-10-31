//
//  HighlightTrigger.h
//  iTerm2
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "Trigger.h"

@interface HighlightTrigger : Trigger

+ (NSString *)title;
- (void)setTextColor:(NSColor *)textColor;
- (void)setBackgroundColor:(NSColor *)backgroundColor;

@end
