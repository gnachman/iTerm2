//
//  HighlightTrigger.h
//  iTerm2
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "Trigger.h"

@protocol iTermColorSettable<NSObject>
- (void)setTextColor:(NSColor *)textColor;
- (void)setBackgroundColor:(NSColor *)backgroundColor;
@end

@interface HighlightTrigger : Trigger<iTermColorSettable>

+ (NSString *)title;

@end
