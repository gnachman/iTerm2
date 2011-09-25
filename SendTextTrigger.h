//
//  SendTextTrigger.h
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//

#import <Cocoa/Cocoa.h>
#import "Trigger.h"

@interface SendTextTrigger : Trigger {

}

- (NSString *)title;
- (BOOL)takesParameter;
- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession;

@end
