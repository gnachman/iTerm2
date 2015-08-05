//
//  CaptureTrigger.h
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "Trigger.h"

@class CapturedOutput;
@class CaptureTrigger;
@class iTermCapturedOutputMark;

@interface CaptureTrigger : Trigger

+ (NSString *)title;
- (void)activateOnOutput:(CapturedOutput *)capturedOutput inSession:(PTYSession *)session;

@end
