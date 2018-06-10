//
//  iTermSessionNameController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/18.
//

#import "iTermSessionNameController.h"

#import "ITAddressBookMgr.h"
#import "iTermBuiltInFunctions.h"
#import "iTermProfilePreferences.h"
#import "iTermScriptFunctionCall.h"
#import "iTermVariables.h"
#import "NSObject+iTerm.h"

static NSString *const iTermSessionNameControllerStateKeyWindowTitleStack = @"window title stack";
static NSString *const iTermSessionNameControllerStateKeyIconTitleStack = @"icon title stack";
static NSString *const iTermSessionNameControllerStateKeyTitleFormat = @"title format";
static NSString *const iTermSessionNameControllerStandardTitleFormat = @"iterm2.private.session_title(session: session.id)";

@interface iTermSessionNameController()
@end

@implementation iTermSessionFormattingDescriptor
@end

@implementation iTermSessionNameController {
    // The window title stack
    NSMutableArray *_windowTitleStack;

    // The icon title stack
    NSMutableArray *_iconTitleStack;

    NSString *_titleFormat;

    NSString *_cachedEvaluatedSessionTitleFormat;
    BOOL _cachedEvaluatedSessionTitleNeedsUpdate;
    NSInteger _count;
    NSInteger _appliedCount;
    NSSet<NSString *> *_dependencies;
}

+ (NSString *)titleFormatForProfile:(Profile *)profile {
    // TODO: When custom functions are supported this will return an appropriate invocation.
    return iTermSessionNameControllerStandardTitleFormat;
}

- (instancetype)initWithTitleFormat:(NSString *)titleFormat {
    self = [super init];
    if (self) {
        _titleFormat = [titleFormat copy];
    }
    return self;
}

- (void)setTitleFormat:(NSString *)titleFormat {
    _titleFormat = [titleFormat copy];
    _cachedEvaluatedSessionTitleFormat = nil;  // This forces a synchronous & async update.
    if (self.delegate) {
        [self updateIfNeeded];
    }
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
              iTermSessionNameControllerStateKeyIconTitleStack: _iconTitleStack ?: @[],
              iTermSessionNameControllerStateKeyTitleFormat: _titleFormat ?: iTermSessionNameControllerStandardTitleFormat };

}

- (void)restoreNameFromStateDictionary:(NSDictionary *)state {
    _windowTitleStack = state[iTermSessionNameControllerStateKeyWindowTitleStack];
    _iconTitleStack = state[iTermSessionNameControllerStateKeyIconTitleStack];
    _titleFormat = state[iTermSessionNameControllerStateKeyTitleFormat] ?: iTermSessionNameControllerStandardTitleFormat;
    [self.delegate sessionNameControllerDidChangeWindowTitle];
}

- (void)variablesDidChange:(NSSet<NSString *> *)names {
    if ([names intersectsSet:_dependencies]) {
        [self setNeedsReevaluation];
    }
}

// Synchronous evaluation updates _dependencies with all paths occurring in the title format.
- (void)evaluateTitleFormatSynchronously:(BOOL)sync
                              completion:(void (^)(NSString *presentationName))completion {
    __weak __typeof(self) weakSelf = self;
    id (^source)(NSString *) = self.delegate.sessionNameControllerVariableSource;
    NSMutableSet *dependencies = [NSMutableSet set];
    [iTermScriptFunctionCall callFunction:_titleFormat
                                  timeout:sync ? 0 : 30
                                   source:^id(NSString *path) {
                                       [dependencies addObject:path];
                                       if (source) {
                                           return source(path);
                                       } else {
                                           return @"";
                                       }
                                   }
                               completion:^(NSString *possiblyEmptyResult, NSError *error) {
                                   NSString *result = [possiblyEmptyResult stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                                   if (error || result.length == 0) {
                                       result = @"🖥";
                                   }
                                   if (!sync) {
                                       [weakSelf didEvaluateTitleFormat:result];
                                   }
                                   completion(result);
                               }];
    _dependencies = dependencies;
}

- (void)didEvaluateTitleFormat:(NSString *)evaluatedTitleFormat {
    _cachedEvaluatedSessionTitleFormat = [evaluatedTitleFormat copy];
    [_delegate sessionNameControllerPresentationNameDidChangeTo:self.presentationSessionTitle];
}

- (NSString *)presentationWindowTitle {
    [self updateIfNeeded];
    return [self formattedName:self.windowNameFromVariable ?: _cachedEvaluatedSessionTitleFormat];
}

- (NSString *)presentationSessionTitle {
    [self updateIfNeeded];
    return [self formattedName:_cachedEvaluatedSessionTitleFormat];
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

- (void)setNeedsUpdate {
    _cachedEvaluatedSessionTitleFormat = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_cachedEvaluatedSessionTitleNeedsUpdate) {
            [self updateIfNeeded];
        }
    });
}

// Forces an async evaluation
- (void)setNeedsReevaluation {
    _cachedEvaluatedSessionTitleNeedsUpdate = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_cachedEvaluatedSessionTitleNeedsUpdate) {
            [self updateIfNeeded];
        }
    });
}

- (void)updateIfNeeded {
    if (!_cachedEvaluatedSessionTitleFormat) {
        _cachedEvaluatedSessionTitleNeedsUpdate = YES;
    }
    if (!_cachedEvaluatedSessionTitleNeedsUpdate) {
        return;
    }
    _cachedEvaluatedSessionTitleNeedsUpdate = NO;
    if (!_cachedEvaluatedSessionTitleFormat) {
        [self updateCachedEvaluatedTitleFormatSynchronously:YES];
    }
    [self updateCachedEvaluatedTitleFormatSynchronously:NO];
}

- (void)updateCachedEvaluatedTitleFormatSynchronously:(BOOL)synchronous {
    __weak __typeof(self) weakSelf = self;
    NSInteger count = ++_count;
    [self evaluateTitleFormatSynchronously:synchronous completion:^(NSString *presentationName) {
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
            if ([NSObject object:strongSelf->_cachedEvaluatedSessionTitleFormat isEqualToObject:presentationName]) {
                return;
            }
            strongSelf->_cachedEvaluatedSessionTitleFormat = [presentationName copy];
            if (!synchronous) {
                [strongSelf.delegate sessionNameControllerPresentationNameDidChangeTo:presentationName];
            }
        }
    }];
}

@end

