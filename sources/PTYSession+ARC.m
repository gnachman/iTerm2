//
//  PTYSession+ARC.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "PTYSession+ARC.h"
#import "PTYSession+Private.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermExpect.h"
#import "iTermExpressionEvaluator.h"
#import "iTermMultiServerJobManager.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermResult.h"
#import "iTermThreadSafety.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"
#import "NSObject+iTerm.h"
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

- (void)failWithError:(NSError *)error {
    DLog(@"%@", error);
    NSString *message =
        [NSString stringWithFormat:@"Cannot start logging to session with profile “%@”: %@",
         self.profile[KEY_NAME],
         error.localizedDescription];
    [iTermWarning showWarningWithTitle:message
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncCannotStartLogging"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Session Logging Problem"
                                window:nil];
}

- (void)fetchAutoLogFilenameWithCompletion:(void (^)(NSString *filename))completion {
    [self setTermIDIfPossible];
    if (![self.profile[KEY_AUTOLOG] boolValue]) {
        completion(nil);
        return;
    }

    iTermMux *mux = [[iTermMux alloc] init];

    NSString *logdirInterpolatedString = [iTermProfilePreferences stringForKey:KEY_LOGDIR inProfile:self.profile];
    NSString *filenameInterpolatedString = [iTermProfilePreferences stringForKey:KEY_LOG_FILENAME_FORMAT inProfile:self.profile];
    [mux evaluateInterpolatedStrings:@[logdirInterpolatedString, filenameInterpolatedString]
                               scope:self.variablesScope
                             timeout:5
                             success:^(NSArray * _Nonnull values) {
        NSString *joined = [self joinedNameWithFolder:values[0] filename:values[1]];
        completion(joined);
    } error:^(NSError * _Nonnull error) {
        [self failWithError:error];
        completion(nil);
    }];
}

- (NSString *)joinedNameWithFolder:(NSString *)formattedFolder
                          filename:(NSString *)formattedFilename {
    NSString *name = [formattedFilename stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
    NSString *joined = [formattedFolder stringByAppendingPathComponent:name];
    DLog(@"folder=%@ filename=%@ name=%@ joined=%@", formattedFolder, formattedFilename, name, joined);
    return joined;
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
                                   after:nil
                                deadline:[NSDate dateWithTimeIntervalSinceNow:0.5]
                              willExpect:nil
                              completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        if ([captureGroups[1] isEqualToString:redflag]) {
            [weakSelf didFindPasteBracketingOopsie];
        }
    }];
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

#pragma mark - Content Subscriptions

- (void)publishNewline {
    if (self.contentSubscribers.count == 0) {
        return;
    }
    static ScreenCharArray *empty;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        screen_char_t placeholder;
        screen_char_t continuation = { 0 };
        continuation.code = EOL_HARD;
        empty = [[ScreenCharArray alloc] initWithLine:&placeholder length:0 continuation:continuation];
    });
    for (id<iTermContentSubscriber> subscriber in self.contentSubscribers) {
        [subscriber deliver:empty metadata:iTermMetadataMakeImmutable(iTermMetadataDefault())];
    }
}

- (void)publishScreenCharArray:(const screen_char_t *)line
                      metadata:(iTermImmutableMetadata)metadata
                        length:(int)length {
    if (self.contentSubscribers.count == 0) {
        return;
    }
    screen_char_t continuation = { 0 };
    continuation.code = EOL_SOFT;
    ScreenCharArray *array = [[ScreenCharArray alloc] initWithLine:(screen_char_t *)line
                                                            length:length
                                                      continuation:continuation];
    for (id<iTermContentSubscriber> subscriber in self.contentSubscribers) {
        [subscriber deliver:array metadata:metadata];
    }
}

@end
