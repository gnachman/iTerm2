//
//  CaptureTrigger.m
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "CaptureTrigger.h"
#import "iTermAnnouncementViewController.h"
#import "PTYSession.h"

static NSString *const kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier =
    @"kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier";

@implementation CapturedOutput

- (void)dealloc {
    [_values release];
    [_trigger release];
    [super dealloc];
}

@end


@implementation CaptureTrigger

- (NSString *)title {
    return @"Capture Output";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)paramPlaceholder {
  return @"Coprocess to run on activation";
}

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession onString:(NSString *)string atAbsoluteLineNumber:(long long)absoluteLineNumber {
    CapturedOutput *output = [[[CapturedOutput alloc] init] autorelease];
    output.line = string;
    output.trigger = self;
    output.values = values;
    output.absoluteLineNumber = absoluteLineNumber;
    [aSession addCapturedOutput:output];
}

- (void)activateOnOutput:(CapturedOutput *)capturedOutput inSession:(PTYSession *)session {
    if (!session.hasCoprocess) {
        NSString *command = [self paramWithBackreferencesReplacedWithValues:capturedOutput.values];
        if (command) {
            [session launchCoprocessWithCommand:command];
        }
    } else {
        iTermAnnouncementViewController *announcement =
            [iTermAnnouncementViewController announcemenWithTitle:@"Can't run two coprocesses at once."
                                                            style:kiTermAnnouncementViewStyleWarning
                                                      withActions:@[ ]
                                                       completion:^(int selection) { }];
        [session queueAnnouncement:announcement
                        identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier];
    }
}

@end
