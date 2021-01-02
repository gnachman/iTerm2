//
//  PTYSession+ARC.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "PTYSession+ARC.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermExpect.h"
#import "iTermExpressionEvaluator.h"
#import "iTermMultiServerJobManager.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermThreadSafety.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"
#import "NSStringITerm.h"
#import "NSWindow+PSM.h"
#import "PTYSession.h"

extern NSString *const SESSION_ARRANGEMENT_TMUX_PANE;
extern NSString *const SESSION_ARRANGEMENT_SERVER_DICT;

@interface iTermPartialAttachment: NSObject<iTermPartialAttachment>
@end

@implementation iTermPartialAttachment
@synthesize partialResult;
@synthesize jobManager;
@synthesize queue;
@end

@interface PTYSession(Private)
@property(nonatomic, retain) iTermExpectation *pasteBracketingOopsieExpectation;
- (void)offerToTurnOffBracketedPasteOnHostChange;
@end

@implementation PTYSession (ARC)

#pragma mark - Arrangements

+ (void)openPartialAttachmentsForArrangement:(NSDictionary *)arrangement
                                  completion:(void (^)(NSDictionary *))completion {
    DLog(@"PTYSession.openPartialAttachmentsForArrangement: start");
    if (arrangement[SESSION_ARRANGEMENT_TMUX_PANE] ||
        ![iTermAdvancedSettingsModel runJobsInServers] ||
        ![iTermMultiServerJobManager available]) {
        DLog(@"PTYSession.openPartialAttachmentsForArrangement: NO, is tmux");
        completion(@{});
        return;
    }
    NSDictionary *restorationIdentifier = [NSDictionary castFrom:arrangement[SESSION_ARRANGEMENT_SERVER_DICT]];
    if (!restorationIdentifier) {
        DLog(@"PTYSession.openPartialAttachmentsForArrangement: NO, lacks server dict\n%@", arrangement[SESSION_ARRANGEMENT_SERVER_DICT]);
        completion(@{});
        return;
    }
    iTermGeneralServerConnection generalConnection;
    if (![iTermMultiServerJobManager getGeneralConnection:&generalConnection
                                fromRestorationIdentifier:restorationIdentifier]) {
        DLog(@"PTYSession.openPartialAttachmentsForArrangement: NO, not multiserver");
        completion(@{});
        return;
    }
    if (generalConnection.type != iTermGeneralServerConnectionTypeMulti) {
        assert(NO);
    }
    const char *label = [iTermThread uniqueQueueLabelWithName:@"com.iterm2.job-manager"].UTF8String;
    dispatch_queue_t jobManagerQueue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL);
    iTermMultiServerJobManager *jobManager =
        [[iTermMultiServerJobManager alloc] initWithQueue:jobManagerQueue];
    DLog(@"PTYSession.openPartialAttachmentsForArrangement: request partial attach");
    [jobManager asyncPartialAttachToServer:generalConnection
                             withProcessID:@(generalConnection.multi.pid)
                                completion:^(id<iTermJobManagerPartialResult> partialResult) {
        DLog(@"PTYSession.openPartialAttachmentsForArrangement: finished");
        if (!partialResult) {
            assert(NO);
            return;
        }
        DLog(@"PTYSession.openPartialAttachmentsForArrangement: SUCCESS for pid %@", @(generalConnection.multi.pid));
        iTermPartialAttachment *attachment = [[iTermPartialAttachment alloc] init];
        attachment.jobManager = jobManager;
        attachment.partialResult = partialResult;
        attachment.queue = jobManagerQueue;
        completion(@{ restorationIdentifier: attachment });
    }];
}

#pragma mark - Attaching

- (BOOL)tryToFinishAttachingToMultiserverWithPartialAttachment:(id<iTermPartialAttachment>)partialAttachment {
    if (!partialAttachment) {
        return NO;
    }
    return [self.shell finishAttachingToMultiserver:partialAttachment.partialResult
                                         jobManager:partialAttachment.jobManager
                                              queue:partialAttachment.queue];
}

#pragma mark - Launching

- (void)fetchAutoLogFilenameWithCompletion:(void (^)(NSString *filename))completion {
    [self setTermIDIfPossible];
    if (![self.profile[KEY_AUTOLOG] boolValue]) {
        completion(nil);
        return;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *format = [iTermAdvancedSettingsModel autoLogFormat];
    iTermExpressionEvaluator *evaluator = [[iTermExpressionEvaluator alloc] initWithInterpolatedString:format scope:self.variablesScope];
    [evaluator evaluateWithTimeout:5
                        completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        if (evaluator.error) {
            NSString *message = [NSString stringWithFormat:@"Cannot start logging to session with profile “%@”: %@",
                                 self.profile[KEY_NAME],
                                 evaluator.error.localizedDescription];
            [iTermWarning showWarningWithTitle:message
                                       actions:@[ @"OK" ]
                                     accessory:nil
                                    identifier:@"NoSyncCannotStartLogging"
                                   silenceable:kiTermWarningTypePersistent
                                       heading:@"Session Logging Problem"
                                        window:nil];
            completion(nil);
            return;
        }
        NSString *name = [evaluator.value stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
        NSString *folder = [iTermProfilePreferences stringForKey:KEY_LOGDIR inProfile:self.profile];
        NSString *filename = [folder stringByAppendingPathComponent:name];
        DLog(@"Using autolog filename %@ from format %@", filename, format);
        completion(filename);
    }];
}

- (void)setTermIDIfPossible {
    if (self.delegate.tabNumberForItermSessionId >= 0) {
        [self.variablesScope setValue:[self.sessionId stringByReplacingOccurrencesOfString:@":" withString:@"."]
                     forVariableNamed:iTermVariableKeySessionTermID];
    }
}

- (void)watchForPasteBracketingOopsieWithPrefix:(NSString *)prefix {
    NSString *const redflag = @"00~";

    if ([prefix hasPrefix:redflag]) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    self.pasteBracketingOopsieExpectation =
    [self.expect expectRegularExpression:[NSString stringWithFormat:@"(%@)?%@", redflag, prefix.it_escapedForRegex]
                              completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        if ([captureGroups[1] isEqualToString:redflag]) {
            [weakSelf didFindPasteBracketingOopsie];
        }
    }];
    [self.expect setTimeout:0.5 forExpectation:self.pasteBracketingOopsieExpectation];
}

- (void)didFindPasteBracketingOopsie {
    [self.expect cancelExpectation:self.pasteBracketingOopsieExpectation];
    [self offerToTurnOffBracketedPasteOnHostChange];
 }

#pragma mark - iTermPopupWindowPresenter

- (void)popupWindowWillPresent:(iTermPopupWindowController *)popupWindowController {
    [self.textview scrollEnd];
}

- (NSRect)popupWindowOriginRectInScreenCoords {
    const int cx = [self.screen cursorX] - 1;
    const int cy = [self.screen cursorY];
    const CGFloat charWidth = [self.textview charWidth];
    const CGFloat lineHeight = [self.textview lineHeight];
    NSPoint p = NSMakePoint([iTermPreferences doubleForKey:kPreferenceKeySideMargins] + cx * charWidth,
                            ([self.screen numberOfLines] - [self.screen height] + cy) * lineHeight);
    const NSPoint origin = [self.textview.window pointToScreenCoords:[self.textview convertPoint:p toView:nil]];
    return NSMakeRect(origin.x,
                      origin.y,
                      charWidth,
                      lineHeight);
}

@end
