//
//  CaptureTrigger.h
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "Trigger.h"

@class CaptureTrigger;
@class iTermCapturedOutputMark;

@interface CapturedOutput : NSObject
@property(nonatomic, copy) NSString *line;
@property(nonatomic, copy) NSArray *values;
@property(nonatomic, retain) CaptureTrigger *trigger;
@property(nonatomic, assign) BOOL state;  // user-defined state
@property(nonatomic, retain) iTermCapturedOutputMark *mark;
@end

@interface CaptureTrigger : Trigger

+ (NSString *)title;
- (void)activateOnOutput:(CapturedOutput *)capturedOutput inSession:(PTYSession *)session;

@end
