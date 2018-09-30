//
//  GrowlTrigger.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "Trigger.h"

// Note: trigger class names can never change because they're stored in prefs.
@interface GrowlTrigger : Trigger

+ (NSString *)title;
- (BOOL)takesParameter;

@end
