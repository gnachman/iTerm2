//
//  iTermSessionNameController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/18.
//

#import "iTermSessionNameController.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAPIHelper.h"
#import "iTermBuiltInFunctions.h"
#import "iTermExpressionParser.h"
#import "iTermProfilePreferences.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

static NSString *const iTermSessionNameControllerStateKeyWindowTitleStack = @"window title stack";
static NSString *const iTermSessionNameControllerStateKeyIconTitleStack = @"icon title stack";
NSString *const iTermSessionNameControllerSystemTitleUniqueIdentifier = @"com.iterm2.system-title";

@interface iTermSessionNameController()
@end

@implementation iTermSessionFormattingDescriptor
@end

@implementation iTermSessionNameController {
    // The window title stack. Contains NSString and NSNull.
    NSMutableArray *_windowTitleStack;

    // The icon title stack. Contains NSString and NSNull.
    NSMutableArray *_iconTitleStack;

    NSString *_cachedEvaluation;
    NSString *_cachedBuiltInWindowTitleEvaluation;
    BOOL _needsUpdate;
    NSInteger _count;
    NSInteger _appliedCount;
    NSArray<iTermVariableReference *> *_refs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didRegisterSessionTitleFunc:)
                                                     name:iTermAPIDidRegisterSessionTitleFunctionNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setDelegate:(id<iTermSessionNameControllerDelegate>)delegate {
    _delegate = delegate;
    if (delegate) {
        [self setNeedsUpdate];
        [self updateIfNeeded];
    }
}

- (NSDictionary *)stateDictionary {
    return @{ iTermSessionNameControllerStateKeyWindowTitleStack: [_windowTitleStack it_arrayByReplacingOccurrencesOf:[NSNull null] with:@0] ?: @[],
              iTermSessionNameControllerStateKeyIconTitleStack: [_iconTitleStack it_arrayByReplacingOccurrencesOf:[NSNull null] with:@0] ?: @[] };
}

- (void)restoreNameFromStateDictionary:(NSDictionary *)state {
    _windowTitleStack = [[state[iTermSessionNameControllerStateKeyWindowTitleStack] it_arrayByReplacingOccurrencesOf:@0 with:[NSNull null]] mutableCopy];
    _iconTitleStack = [[state[iTermSessionNameControllerStateKeyIconTitleStack] it_arrayByReplacingOccurrencesOf:@0 with:[NSNull null]] mutableCopy];
    [self.delegate sessionNameControllerDidChangeWindowTitle];
}

- (NSString *)invocationForTitleProviderID:(NSString *)uniqueIdentifier {
    if ([uniqueIdentifier isEqualToString:iTermSessionNameControllerSystemTitleUniqueIdentifier]) {
        return @"iterm2.private.session_title(session: session.id)";
    }
    return [[iTermAPIHelper sessionTitleFunctions] objectPassingTest:^BOOL(iTermSessionTitleProvider *provider, NSUInteger index, BOOL *stop) {
        return [provider.uniqueIdentifier isEqualToString:uniqueIdentifier];
    }].invocation;
}

- (BOOL)usingBuiltInTitleProvider {
    NSString *uniqueIdentifier = self.delegate.sessionNameControllerUniqueIdentifier;
    return [uniqueIdentifier isEqualToString:iTermSessionNameControllerSystemTitleUniqueIdentifier];
}

// Synchronous evaluation updates _dependencies with all paths occurring in the title format.
- (void)evaluateInvocationSynchronously:(BOOL)sync
                             completion:(void (^)(NSString *presentationName))completion {
    __weak __typeof(self) weakSelf = self;
    iTermVariableScope *scope;
    iTermVariableRecordingScope *recordingScope;  // either nil or equal to scope
    if (sync) {
        recordingScope = [self.delegate.sessionNameControllerScope recordingCopy];
        scope.neverReturnNil = YES;
        scope = recordingScope;
    } else {
        scope = self.delegate.sessionNameControllerScope;
    }
    NSString *uniqueIdentifier = self.delegate.sessionNameControllerUniqueIdentifier;
    if (!uniqueIdentifier) {
        [self didEvaluateInvocationWithResult:@""];
        completion(@"");
        return;
    }
    NSString *invocation = [self invocationForTitleProviderID:uniqueIdentifier];
    if (!invocation) {
        [self didEvaluateInvocationWithResult:@"…"];
        completion(@"…");
        return;
    }
    [iTermScriptFunctionCall callFunction:invocation
                                  timeout:sync ? 0 : 30
                                    scope:scope
                               retainSelf:YES
                               completion:
     ^(NSString *possiblyEmptyResult, NSError *error, NSSet<NSString *> *missing) {
         NSString *result = [weakSelf valueForInvocation:invocation
                                              withResult:possiblyEmptyResult
                                                   error:error];
         if (error) {
             [weakSelf logError:error forInvocation:invocation];
         }
         if (!sync) {
             [weakSelf didEvaluateInvocationWithResult:result];
         }
         completion(result);
     }];
    if ([uniqueIdentifier isEqualToString:iTermSessionNameControllerSystemTitleUniqueIdentifier]) {
        // Do it again to get the window title. We know this completes synchronously.
        __block NSString *windowTitle = nil;
        [iTermScriptFunctionCall callFunction:@"iterm2.private.window_title(session: session.id)"
                                      timeout:0
                                        scope:scope
                                   retainSelf:YES
                                   completion:
         ^(NSString *possiblyEmptyResult, NSError *error, NSSet<NSString *> *missing) {
             windowTitle = [weakSelf valueForInvocation:invocation
                                             withResult:possiblyEmptyResult
                                                  error:error];
         }];
        _cachedBuiltInWindowTitleEvaluation = windowTitle;
    } else {
        _cachedBuiltInWindowTitleEvaluation = nil;
    }
    if (recordingScope) {
        // Add tmux variables we use for adding formatting.
        for (NSString *tmuxVariableName in @[ iTermVariableKeySessionTmuxClientName,
                                              iTermVariableKeySessionTmuxRole,
                                              iTermVariableKeySessionTmuxPaneTitle ]) {
            [scope valueForVariableName:tmuxVariableName];
        }
        for (iTermVariableReference *ref in _refs) {
            [ref removeAllLinks];
        }
        _refs = recordingScope.recordedReferences;
        for (iTermVariableReference *ref in _refs) {
            ref.onChangeBlock = ^{
                [weakSelf setNeedsReevaluation];
            };
        }
    }
}

- (BOOL)errorIsUnregisteredFunctionCall:(NSError *)error {
    return (error.code == iTermAPIHelperErrorCodeUnregisteredFunction &&
            [error.domain isEqual:iTermAPIHelperErrorDomain]);
}

- (void)logError:(NSError *)error forInvocation:(NSString *)invocation {
    NSString *message = [NSString stringWithFormat:@"Invoked “%@” to compute name for session. Failed with error:\n%@\n",
                         invocation,
                         [error localizedDescription]];
    NSString *detail = error.localizedFailureReason;
    if (detail) {
        message = [message stringByAppendingFormat:@"%@\n", detail];
    }
    NSString *connectionKey = error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] entryWithIdentifier:connectionKey];
    if (!entry) {
        entry = [iTermScriptHistoryEntry globalEntry];
    }
    [entry addOutput:message];
    if ([self errorIsUnregisteredFunctionCall:error]) {
        [self logMessage:[NSString stringWithFormat:@"Could not make a function call into a script. Either its unique identifier changed (in which case you should update your settings in Prefs > Profiles > General > Title) or the script is not running. The failed invocation was:\n%@", invocation]
              invocation:invocation];
    } else {
        [self logMessage:error.localizedDescription
              invocation:invocation];
    }
}

- (NSString *)valueForInvocation:(NSString *)invocation
                      withResult:(NSString *)possiblyEmptyResult
                           error:(NSError *)error {
    if (!error) {
        NSString *result = [possiblyEmptyResult stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (result.length == 0) {
            result = @" ";
        }
        return result;
    }

    const BOOL isUnregistered = [self errorIsUnregisteredFunctionCall:error];
    return isUnregistered ? @"…" : @"🐞";
}

- (void)logMessage:(NSString *)message invocation:(NSString *)invocation {
    NSError *invocationError = nil;
    NSString *signature = [iTermExpressionParser signatureForFunctionCallInvocation:invocation error:&invocationError];
    if (signature) {
        [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:signature
                                                                              string:message];
    } else {
        [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:nil
                                                                              format:@"Malformed invocation in session name controller. The invocation is:\n%@\nIt doesn't look like a function call! The parser said:\n",
         invocation,
         invocationError.localizedDescription];
    }
}

- (void)didEvaluateInvocationWithResult:(NSString *)result {
    _cachedEvaluation = [result copy];
    [_delegate sessionNameControllerNameWillChangeTo:_cachedEvaluation];
    [_delegate sessionNameControllerPresentationNameDidChangeTo:self.presentationSessionTitle];
}

- (NSString *)presentationWindowTitle {
    [self updateIfNeeded];

    if ([self usingBuiltInTitleProvider] && _cachedBuiltInWindowTitleEvaluation) {
        // We're using a standard window title (not provided by a script). Use the window version of
        // the session title. This combines the OSC 0/2 window title (if any) with other title components.
        return [self formattedName:_cachedBuiltInWindowTitleEvaluation];
    } else if (self.windowNameFromVariable) {
        // Using a custom title provider and there's an OSC 0/OSC 2 window title set. That overrides
        // the title provider's value. Some day I should add support for window title providers, but
        // for now they are just *session* title providers.
        return [self formattedName:self.windowNameFromVariable];
    } else {
        // Either we're using a builtin title provider but haven't cached it for some reason (this
        // should not happen), or there's a custom title provider not overridden by OSC 0/OSC 2.
        // Finally, if lots of impossible things happen return Unnamed so we
        // can correlate bug reports with this comment. Hi, future me.
        return [self formattedName:_cachedEvaluation ?: @"Unnamed"];
    }
}

- (NSString *)presentationSessionTitle {
    [self updateIfNeeded];
    return [self formattedName:_cachedEvaluation];
}

#pragma mark - Stacks

- (void)pushWindowTitle {
    if (!_windowTitleStack) {
        // initialize lazily
        _windowTitleStack = [[NSMutableArray alloc] init];
    }
    id title = self.windowNameFromVariable;
    if (!title) {
        // if current title is nil, treat it as an empty string.
        title = [NSNull null];
    }
    // push it
    [_windowTitleStack addObject:title];
    DLog(@"Pushed window title. Stack is now %@", _windowTitleStack);
}

- (NSString *)popWindowTitle {
    // Ignore if title stack is nil or stack count == 0
    NSUInteger count = [_windowTitleStack count];
    if (count > 0) {
        // pop window title
        id result = [_windowTitleStack objectAtIndex:count - 1];
        [_windowTitleStack removeObjectAtIndex:count - 1];
        DLog(@"Popped window title %@. Stack is now %@", result, _windowTitleStack);
        return [result nilIfNull];
    } else {
        return nil;
    }
}

- (void)pushIconTitle {
    if (!_iconTitleStack) {
        // initialize lazily
        _iconTitleStack = [[NSMutableArray alloc] init];
    }
    iTermVariableScope *scope = [self.delegate sessionNameControllerScope];
    id title = [scope valueForVariableName:iTermVariableKeySessionIconName];
    if (!title) {
        // if current icon title is nil, treat it as an empty string.
        title = [NSNull null];
    }
    // push it
    [_iconTitleStack addObject:title];
    DLog(@"Pushed icon title. Stack is now %@", _iconTitleStack);
}

- (NSString *)popIconTitle {
    // Ignore if icon title stack is nil or stack count == 0.
    NSUInteger count = [_iconTitleStack count];
    if (count > 0) {
        // pop icon title
        NSString *result = [_iconTitleStack objectAtIndex:count - 1];
        [_iconTitleStack removeObjectAtIndex:count - 1];
        DLog(@"Popped icon title %@. Stack is now %@", result, _iconTitleStack);
        return [result nilIfNull];
    } else {
        return nil;
    }
}

#pragma mark - Private

- (NSString *)windowNameFromVariable {
    iTermVariableScope *scope = [self.delegate sessionNameControllerScope];
    return [scope valueForVariableName:iTermVariableKeySessionWindowName];
}

- (NSString *)formattedName:(NSString *)base {
    iTermSessionFormattingDescriptor *descriptor = [self.delegate sessionNameControllerFormattingDescriptor];
    if (descriptor.isTmuxGateway) {
        return [NSString stringWithFormat:@"[↣ %@ %@]", base, descriptor.tmuxClientName];
    }
    if (descriptor.haveTmuxController) {
        // There won't be a valid job name, and the profile name is always tmux, so just show the
        // window name. This is confusing: this refers to the name of a tmux window, which is
        // equivalent to an iTerm2 tab. It is reported to us by tmux. We ignore the base name
        // because the real name comes from the server and that's all we care about.
        if (self.delegate.sessionNameControllerUniqueIdentifier) {
            // Using a custom title provider.
            return [NSString stringWithFormat:@"↣ %@", base];
        } else {
            return [NSString stringWithFormat:@"↣ %@", descriptor.tmuxWindowName];
        }
    }
    return base;
}

// Forces sync followed by async eval. Use this when the invocation changes.
- (void)setNeedsUpdate {
    [self evaluateInvocationSynchronously:YES];
    [self setNeedsReevaluation];
}

// Forces only an async eval. Use this when inputs to the invocation change.
- (void)setNeedsReevaluation {
    _needsUpdate = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_needsUpdate) {
            [self updateIfNeeded];
        }
    });
}

- (void)updateIfNeeded {
    if (!_cachedEvaluation) {
        _needsUpdate = YES;
    }
    if (!_needsUpdate) {
        return;
    }
    _needsUpdate = NO;
    if (!_cachedEvaluation) {
        [self evaluateInvocationSynchronously:YES];
    }
    [self evaluateInvocationSynchronously:NO];
}

- (void)evaluateInvocationSynchronously:(BOOL)synchronous {
    __weak __typeof(self) weakSelf = self;
    NSInteger count = ++_count;
    [self evaluateInvocationSynchronously:synchronous completion:^(NSString *presentationName) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            if (strongSelf->_appliedCount > count) {
                // A later async evaluation has already completed. Don't overwrite it.
                return;
            }
            strongSelf->_appliedCount = count;
            if (!presentationName) {
                presentationName = @"Untitled";
            }
            if ([NSObject object:strongSelf->_cachedEvaluation isEqualToObject:presentationName]) {
                return;
            }
            strongSelf->_cachedEvaluation = [presentationName copy];
            if (!synchronous) {
                [strongSelf.delegate sessionNameControllerPresentationNameDidChangeTo:presentationName];
            }
        }
    }];
}

#pragma mark - Notifications

- (void)didRegisterSessionTitleFunc:(NSNotification *)notification {
    _cachedEvaluation = nil;  // Force references to be recomputed
    [self setNeedsReevaluation];
}

@end

