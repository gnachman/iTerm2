//
//  AlertTrigger.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "Trigger.h"

@interface AlertTrigger : Trigger {
    BOOL disabled_;
}

+ (NSString *)title;
- (BOOL)takesParameter;

@end
