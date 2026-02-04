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
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSWindow+PSM.h"
#import "PTYSession+Private.h"
#import "PTYSession.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAnnouncementViewController.h"
#import "iTermComposerManager.h"
#import "iTermExpect.h"
#import "iTermExpressionEvaluator.h"
#import "iTermMultiServerJobManager.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermResult.h"
#import "iTermThreadSafety.h"
#import "iTermUserDefaults.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"

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
- (void)offerToRestoreIconName:(NSString *)iconName windowName:(NSString *)windowName;
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

- (iTermJobManagerAttachResults)tryToFinishAttachingToMultiserverWithPartialAttachment:(id<iTermPartialAttachment>)partialAttachment {
    if (!partialAttachment) {
        return 0;
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
                  sideEffectsAllowed:YES
                           retryTime:5
                             success:^(NSArray<NSString *> *values) {
        NSString *folder = values[0];
        if (folder.length == 0) {
            folder = NSHomeDirectory();
        }
        NSString *joined = [self joinedNameWithFolder:folder filename:values[1]];
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
    return [joined stringByExpandingTildeInPath];
}

- (void)setTermIDIfPossible {
    if (self.delegate.tabNumberForItermSessionId >= 0) {
        [self.variablesScope setValue:[self.sessionId stringByReplacingOccurrencesOfString:@":" withString:@"."]
                     forVariableNamed:iTermVariableKeySessionTermID];
    }
}

- (void)watchForPasteBracketingOopsieWithPrefix:(NSString *)prefix
                                       andWrite:(NSString *)string {
    NSString *const redflag = @"00~";

    if ([prefix hasPrefix:redflag]) {
        [self writeTask:string];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    self.pasteBracketingOopsieExpectation =
    [_expect expectRegularExpression:[NSString stringWithFormat:@"(%@)?%@", redflag, prefix.it_escapedForRegex]
                               after:nil
                            deadline:[NSDate dateWithTimeIntervalSinceNow:0.5]
                          willExpect:^{
        DLog(@"Write task");
        [weakSelf writeTask:string];
    }
                          completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        if ([captureGroups[1] isEqualToString:redflag]) {
            [weakSelf didFindPasteBracketingOopsie];
        }
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        DLog(@"Sync expectations");
        [weakSelf sync];
    });
}

- (iTermExpectation *)addExpectation:(NSString *)regex
                               after:(nullable iTermExpectation *)predecessor
                            deadline:(nullable NSDate *)deadline
                          willExpect:(void (^ _Nullable)(void))willExpect
                          completion:(void (^ _Nullable)(NSArray<NSString *> * _Nonnull))completion {
    return [_expect expectRegularExpression:regex
                                      after:predecessor
                                   deadline:deadline
                                 willExpect:willExpect
                                 completion:completion];
}

- (void)didFindPasteBracketingOopsie {
    [_expect cancelExpectation:self.pasteBracketingOopsieExpectation];
    [self maybeTurnOffPasteBracketing];
}

- (void)maybeTurnOffPasteBracketing {
    NSNumber *number = [[iTermUserDefaults userDefaults] objectForKey:kTurnOffBracketedPasteOnHostChangeUserDefaultsKey];
    if (number.boolValue) {
        [self.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                     VT100ScreenMutableState *mutableState,
                                                     id<VT100ScreenDelegate> delegate) {
            terminal.bracketedPasteMode = NO;
        }];
    } else if (!number) {
        [self offerToTurnOffBracketedPasteOnHostChange];
    }
 }

- (void)maybeOfferToRestoreIconName:(NSString *)iconName windowName:(NSString *)windowName {
    if (![iTermProfilePreferences boolForKey:KEY_ALLOW_TITLE_SETTING inProfile:self.profile]) {
        return;
    }
    NSNumber *number = [[iTermUserDefaults userDefaults] objectForKey:kRestoreIconAndWindowNameOnHostChangeUserDefaultsKey];
    if (number.boolValue) {
        [self naggingControllerRestoreIconNameTo:iconName windowName:windowName];
    } else if (!number) {
        [self offerToRestoreIconName:iconName windowName:windowName];
    }
}

#pragma mark - iTermPopupWindowPresenter

- (void)popupWindowWillPresent:(iTermPopupWindowController *)popupWindowController {
    [self.textview scrollEnd];
}

- (id<iTermPopupWindowHosting>)popupHost {
    NSResponder *responder = [self.view.window firstResponder];
    while (responder) {
        if ([responder conformsToProtocol:@protocol(iTermPopupWindowHosting)]) {
            id<iTermPopupWindowHosting> host = (id<iTermPopupWindowHosting>)responder;
            return host;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

- (NSRect)popupWindowOriginRectInScreenCoords {
    if (self.isBrowserSession) {
        const NSRect viewBounds = self.view.bounds;
        const NSRect cursorRectInViewCoords = NSMakeRect(NSMidX(viewBounds), 0, 1, 1);
        const NSRect cursorRectInWindowCoords = [self.view convertRect:cursorRectInViewCoords toView:nil];
        const NSRect cursorRectInScreenCoords = [self.view.window convertRectToScreen:cursorRectInWindowCoords];
        return cursorRectInScreenCoords;
    }
    id<iTermPopupWindowHosting> host = [self popupHost];
    if (!host) {
        return [self textViewCursorFrameInScreenCoords];
    }
    return [host popupWindowHostingInsertionPointFrameInScreenCoordinates];
}

#pragma mark - Content Subscriptions

- (void)publishNewlineWithLineBufferGeneration:(long long)lineBufferGeneration {
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
        [empty makeSafe];
    });
    // Dispatch because side-effects can't join the mutation queue.
    [self publishScreenCharArray:empty 
                        metadata:iTermMetadataMakeImmutable(iTermMetadataDefault())
            lineBufferGeneration:lineBufferGeneration];
}

- (void)publishScreenCharArray:(ScreenCharArray *)array
                      metadata:(iTermImmutableMetadata)metadata
          lineBufferGeneration:(long long)lineBufferGeneration {
    if (self.contentSubscribers.count == 0) {
        return;
    }
    [self publish:[PTYSessionPublishRequest requestWithArray:array
                                                    metadata:metadata
                                        lineBufferGeneration:lineBufferGeneration]];
}

- (void)publish:(PTYSessionPublishRequest *)request {
    [_pendingPublishRequests addObject:request];
    if (_havePendingPublish) {
        return;
    }
    _havePendingPublish = YES;
    // Side-effects are not allowed to join the mutation thread so publish not as a side-effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self sendPendingPublishRequests];
    });
}

- (void)sendPendingPublishRequests {
    _havePendingPublish = NO;
    DLog(@"Begin sending pending publish requests. Queue size is %@", @(_pendingPublishRequests.count));
    iTermDeadlineMonitor *deadline = [[iTermDeadlineMonitor alloc] initWithDuration:0.1];
    while (_pendingPublishRequests.count && deadline.pending) {
        PTYSessionPublishRequest *request = _pendingPublishRequests.firstObject;
        [_pendingPublishRequests removeObjectAtIndex:0];
        for (id<iTermContentSubscriber> subscriber in self.contentSubscribers) {
            [subscriber updateMetadataWithSelectedCommandRange:self.textview.findOnPageHelper.absLineRange
                                            cumulativeOverflow:self.screen.totalScrollbackOverflow];
            [subscriber deliver:request.array
                       metadata:request.metadata
           lineBufferGeneration:request.lineBufferGeneration];
        }
    }
    DLog(@"Done sending pending publish requests. Queue size is %@", @(_pendingPublishRequests.count));
    if (_pendingPublishRequests.count) {
        DLog(@"Schedule another update");
        __weak __typeof(self) weakSelf = self;
        _havePendingPublish = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf sendPendingPublishRequests];
        });
    }
}

#pragma mark - AITerm

- (void)removeAITerm {
    [_aiterm invalidate];
    _aiterm = nil;
}

- (void)setAITerm:(AITermControllerObjC *)aiterm {
    [self removeAITerm];
    _aiterm = aiterm;
}


@end

@implementation PTYSessionPublishRequest

+ (instancetype)requestWithArray:(ScreenCharArray *)sca 
                        metadata:(iTermImmutableMetadata)metadata
            lineBufferGeneration:(long long)lineBufferGeneration {
    PTYSessionPublishRequest *request = [[PTYSessionPublishRequest alloc] init];
    request->_lineBufferGeneration = lineBufferGeneration;
    [sca makeSafe];
    request->_array = sca;
    iTermImmutableMetadataRetain(metadata);
    request->_metadata = metadata;
    return request;
}

- (void)dealloc {
    iTermImmutableMetadataRelease(_metadata);
}

@end
