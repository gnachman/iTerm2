//
//  iTermSessionNameController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/18.
//

#import "iTermSessionNameController.h"

#import "ITAddressBookMgr.h"
#import "iTermAPIHelper.h"
#import "iTermBuiltInFunctions.h"
#import "iTermProfilePreferences.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermVariables.h"
#import "NSObject+iTerm.h"

static NSString *const iTermSessionNameControllerStateKeyWindowTitleStack = @"window title stack";
static NSString *const iTermSessionNameControllerStateKeyIconTitleStack = @"icon title stack";

@interface iTermSessionNameController()
@end

@implementation iTermSessionFormattingDescriptor
@end

@implementation iTermSessionNameController {
    // The window title stack
    NSMutableArray *_windowTitleStack;

    // The icon title stack
    NSMutableArray *_iconTitleStack;

    NSString *_cachedEvaluation;
    BOOL _needsUpdate;
    NSInteger _count;
    NSInteger _appliedCount;
    NSSet<NSString *> *_dependencies;
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
    return @{ iTermSessionNameControllerStateKeyWindowTitleStack: _windowTitleStack ?: @[],
              iTermSessionNameControllerStateKeyIconTitleStack: _iconTitleStack ?: @[] };
}

- (void)restoreNameFromStateDictionary:(NSDictionary *)state {
    _windowTitleStack = [state[iTermSessionNameControllerStateKeyWindowTitleStack] mutableCopy];
    _iconTitleStack = [state[iTermSessionNameControllerStateKeyIconTitleStack] mutableCopy];
    [self.delegate sessionNameControllerDidChangeWindowTitle];
}

- (void)variablesDidChange:(NSSet<NSString *> *)names {
    if ([names intersectsSet:_dependencies]) {
        [self setNeedsReevaluation];
    }
}

// Synchronous evaluation updates _dependencies with all paths occurring in the title format.
- (void)evaluateInvocationSynchronously:(BOOL)sync
                             completion:(void (^)(NSString *presentationName))completion {
    __weak __typeof(self) weakSelf = self;
    id (^source)(NSString *) = self.delegate.sessionNameControllerVariableSource;
    NSMutableSet *dependencies;
    if (sync) {
        dependencies = [NSMutableSet set];
    }
    NSString *invocation = self.delegate.sessionNameControllerInvocation;
    if (!invocation) {
        [self didEvaluateInvocationWithResult:@""];
        completion(@"");
        return;
    }
    [iTermScriptFunctionCall callFunction:invocation
                                  timeout:sync ? 0 : 30
                                   source:^id(NSString *path) {
                                       [dependencies addObject:path];
                                       if (source) {
                                           return source(path);
                                       } else {
                                           return @"";
                                       }
                                   }
                               completion:
     ^(NSString *possiblyEmptyResult, NSError *error, NSSet<NSString *> *missing) {
         if (error) {
             NSString *message =
             [NSString stringWithFormat:@"Invoked “%@” to compute name for session. Failed with error:\n%@\n",
              invocation,
              [error localizedDescription]];
             NSString *detail = error.localizedFailureReason;
             if (detail) {
                 message = [message stringByAppendingFormat:@"%@\n", detail];
             }
             NSString *connectionKey =
                 error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
             iTermScriptHistoryEntry *entry =
                [[iTermScriptHistory sharedInstance] entryWithIdentifier:connectionKey];
             if (!entry) {
                 entry = [iTermScriptHistoryEntry globalEntry];
             }
             [entry addOutput:message];
         }

         NSString *result = [possiblyEmptyResult stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
         if (error) {
             if (error.code == iTermAPIHelperFunctionCallUnregisteredErrorCode &&
                 [error.domain isEqual:@"com.iterm2.api"]) {
                 // Waiting for the function to be registered
                 result = @"…";
             } else {
                 result = @"🐞";
             }
         } else if (result.length == 0) {
             result = @"🖥";
         }
         if (!sync) {
             [weakSelf didEvaluateInvocationWithResult:result];
         }
         completion(result);
     }];
    if (sync) {
        // Add tmux variables we use for adding formatting.
        _dependencies = [dependencies setByAddingObjectsFromArray:@[ iTermVariableKeySessionTmuxClientName,
                                                                     iTermVariableKeySessionTmuxRole,
                                                                     iTermVariableKeySessionTmuxWindowTitle ]];
    }
}

- (void)didEvaluateInvocationWithResult:(NSString *)result {
    _cachedEvaluation = [result copy];
    [_delegate sessionNameControllerNameWillChangeTo:_cachedEvaluation];
    [_delegate sessionNameControllerPresentationNameDidChangeTo:self.presentationSessionTitle];
}

- (NSString *)presentationWindowTitle {
    [self updateIfNeeded];
    return [self formattedName:self.windowNameFromVariable ?: _cachedEvaluation];
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
    NSString *title = self.windowNameFromVariable;
    if (!title) {
        // if current title is nil, treat it as an empty string.
        title = @"";
    }
    // push it
    [_windowTitleStack addObject:title];
}

- (NSString *)popWindowTitle {
    // Ignore if title stack is nil or stack count == 0
    NSUInteger count = [_windowTitleStack count];
    if (count > 0) {
        // pop window title
        NSString *result = [_windowTitleStack objectAtIndex:count - 1];
        [_windowTitleStack removeObjectAtIndex:count - 1];
        return result;
    } else {
        return nil;
    }
}

- (void)pushIconTitle {
    if (!_iconTitleStack) {
        // initialize lazily
        _iconTitleStack = [[NSMutableArray alloc] init];
    }
    NSString *title = [self.delegate sessionNameControllerVariableSource](iTermVariableKeySessionIconName);
    if (!title) {
        // if current icon title is nil, treat it as an empty string.
        title = @"";
    }
    // push it
    [_iconTitleStack addObject:title];
}

- (NSString *)popIconTitle {
    // Ignore if icon title stack is nil or stack count == 0.
    NSUInteger count = [_iconTitleStack count];
    if (count > 0) {
        // pop icon title
        NSString *result = [_iconTitleStack objectAtIndex:count - 1];
        [_iconTitleStack removeObjectAtIndex:count - 1];
        return result;
    } else {
        return nil;
    }
}

#pragma mark - Private

- (NSString *)windowNameFromVariable {
    return [self.delegate sessionNameControllerVariableSource](iTermVariableKeySessionWindowName);
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
        return [NSString stringWithFormat:@"↣ %@", descriptor.tmuxWindowName];
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
    [self setNeedsReevaluation];
}

@end

