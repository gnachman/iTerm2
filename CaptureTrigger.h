//
//  CaptureTrigger.h
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "Trigger.h"

@class CaptureTrigger;

@interface CapturedOutput : NSObject
@property(nonatomic, copy) NSString *line;
@property(nonatomic, copy) NSArray *values;
@property(nonatomic, retain) CaptureTrigger *trigger;
@property(nonatomic, assign) long long absoluteLineNumber;
@property(nonatomic, assign) BOOL state;  // user-defined state
@end

@interface CaptureTrigger : Trigger

- (void)activateOnOutput:(CapturedOutput *)capturedOutput inSession:(PTYSession *)session;

@end
