//
//  iTermSessionNameController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/18.
//

#import "iTermSessionNameController.h"

#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "iTermScriptFunctionCall.h"
#import "NSObject+iTerm.h"

@interface iTermSessionNameController()
@end

@implementation iTermSessionFormattingDescriptor
@end

@implementation iTermSessionNameController {
    // The window title stack
    NSMutableArray *_windowTitleStack;

    // The icon title stack
    NSMutableArray *_iconTitleStack;

    NSString *_profileName;
    NSString *_titleFormat;

    NSString *_cachedEvaluatedTitleFormat;
#warning TODO: Set this when a variable we use changes
    BOOL _cachedEvaluatedTitleFormatInvalid;
}

+ (NSString *)titleFormatForProfile:(Profile *)profile {
    NSUInteger titleComponents = [iTermProfilePreferences unsignedIntegerForKey:KEY_TITLE_COMPONENTS
                                                                      inProfile:profile];
    if (titleComponents & iTermTitleComponentsLegacy) {
        return @"\(iterm2.private.legacy_title(session.id))";
    }
    if (titleComponents & iTermTitleComponentsCustom) {
        return [iTermProfilePreferences stringForKey:KEY_CUSTOM_TITLE
                                           inProfile:profile];
    }

    NSMutableArray<NSString *> *components = [NSMutableArray array];
    if (titleComponents & iTermTitleComponentsProfileName) {
        [components addObject:@"\\(session.name)"];
    }
    if (titleComponents & iTermTitleComponentsJob) {
        [components addObject:@"\\(session.job.name)"];
    }
    if (titleComponents & iTermTitleComponentsWorkingDirectory) {
        [components addObject:@"\\(session.path)"];
    }
    if (titleComponents & iTermTitleComponentsTTY) {
        [components addObject:@"\\(session.tty)"];
    }

    return [components componentsJoinedByString:@" — "];
}

- (instancetype)initWithProfileName:(NSString *)profileName
                        titleFormat:(NSString *)titleFormat {
    self = [super init];
    if (self) {
        _firstSessionName = [profileName copy];
        _sessionName = [profileName copy];
        _profileName = [profileName copy];
        _titleFormat = [titleFormat copy];
    }
    return self;
}

- (NSDictionary *)stateDictionary {
#warning TODO
    return @{};
}

- (void)restoreNameFromStateDictionary:(NSDictionary *)state
                     legacyProfileName:(NSString *)legacyProfileName
                     legacySessionName:(NSString *)legacyName
                     legacyWindowTitle:(NSString *)legacyWindowTitle {
    if (state) {
#warning TODO
    } else {
        _profileName = [legacyProfileName copy];
        if (legacyName) {
            [self setSessionName:legacyName];
        }
        if (legacyWindowTitle) {
            [self setWindowTitle:legacyWindowTitle];
        }
    }
    [self.delegate sessionNameControllerDidChangeWindowTitle];
}

- (void)didInitializeSessionWithName:(NSString *)newName {
    [self setSessionName:newName];
}

- (void)profileDidChangeToProfileWithName:(NSString *)newName {
    if ([self.sessionName isEqualToString:_profileName]) {
        [self setSessionName:newName.copy];
    }
    _profileName = [newName copy];
}

- (void)profileNameDidChangeTo:(NSString *)newName {
    // Set name, which overrides any session-set icon name.
    [self setSessionName:newName.copy];
    // set default name, which will appear as a prefix if the session changes the name.
    _profileName = newName.copy;
}

- (void)terminalDidSetWindowTitle:(NSString *)newName {
    _terminalWindowName = [newName copy];
    self.windowTitle = newName;
}

- (void)terminalDidSetIconTitle:(NSString *)newName {
    _terminalIconName = [newName copy];
    self.sessionName = newName;
}

- (void)triggerDidChangeNameTo:(NSString *)newName {
    self.sessionName = newName;
}

- (void)setTmuxTitle:(NSString *)tmuxTitle {
    self.sessionName = tmuxTitle;
    self.windowTitle = tmuxTitle;
}

- (void)didSynthesizeFrom:(iTermSessionNameController *)real {
    self.sessionName = real.sessionName;
}

- (void)setSessionName:(NSString *)theName {
    [self.delegate sessionNameControllerNameWillChangeTo:theName];
    if (!_firstSessionName) {
        _firstSessionName = theName;
    }
    if ([_sessionName isEqualToString:theName]) {
        return;
    }

    if (_sessionName) {
        // clear the window title if it is not different
        if ([_sessionName isEqualToString:_windowTitle]) {
            _windowTitle = nil;
        }
        _sessionName = nil;
    }
    if (!theName) {
        theName = @"Untitled";
    }

    _sessionName = [theName copy];
    // sync the window title if it is not set to something else
    if (_windowTitle == nil) {
        [self setWindowTitle:theName];
    }

    __weak __typeof(self) weakSelf = self;
    [self evaluatePresentationNameSynchronously:NO completion:^(NSString *presentationName) {
        [weakSelf.delegate sessionNameControllerPresentationNameDidChangeTo:presentationName];
    }];
}

- (void)evaluatePresentationNameSynchronously:(BOOL)sync
                                   completion:(void (^)(NSString *presentationName))completion {
    __weak __typeof(self) weakSelf = self;
    [iTermScriptFunctionCall evaluateString:_titleFormat
                                    timeout:sync ? 0 : 30
                                     source:self.delegate.sessionNameControllerVariableSource
                                 completion:^(NSString *result, NSError *error) {
                                     if (!sync) {
                                         [weakSelf didEvaluateTitleFormat:result error:error];
                                     }
                                     completion(result);
                                 }];
}

- (void)didEvaluateTitleFormat:(NSString *)formattedTitle error:(NSError *)error {
    if (!error) {
        _cachedEvaluatedTitleFormat = [self formattedName:_cachedEvaluatedTitleFormat];
        [_delegate sessionNameControllerPresentationNameDidChangeTo:_cachedEvaluatedTitleFormat];
    }
}

- (NSString *)presentationWindowTitle {
    if (!_windowTitle) {
        return nil;
    }
    return [self formattedName:_windowTitle];
}

- (void)setWindowTitle:(NSString *)windowTitle {
    if ([windowTitle isEqualToString:_windowTitle]) {
        return;
    }

    if (windowTitle != nil && [windowTitle length] > 0) {
        _windowTitle = [windowTitle copy];
    } else {
        _windowTitle = nil;
    }

    [self.delegate sessionNameControllerDidChangeWindowTitle];
}

- (NSString *)presentationName {
    [self updateCachedEvaluatedTitleFormatIfNeeded];
    return [self formattedName:_cachedEvaluatedTitleFormat];
}

- (void)pushWindowTitle {
    if (!_windowTitleStack) {
        // initialize lazily
        _windowTitleStack = [[NSMutableArray alloc] init];
    }
    NSString *title = self.windowTitle;
    if (!title) {
        // if current title is nil, treat it as an empty string.
        title = @"";
    }
    // push it
    [_windowTitleStack addObject:title];
}

- (void)popWindowTitle {
    // Ignore if title stack is nil or stack count == 0
    NSUInteger count = [_windowTitleStack count];
    if (count > 0) {
        // pop window title
        [self setWindowTitle:[_windowTitleStack objectAtIndex:count - 1]];
        [_windowTitleStack removeObjectAtIndex:count - 1];
    }
}

- (void)pushIconTitle {
    if (!_iconTitleStack) {
        // initialize lazily
        _iconTitleStack = [[NSMutableArray alloc] init];
    }
    NSString *title = self.sessionName;
    if (!title) {
        // if current icon title is nil, treat it as an empty string.
        title = @"";
    }
    // push it
    [_iconTitleStack addObject:title];
}

- (void)popIconTitle {
    // Ignore if icon title stack is nil or stack count == 0.
    NSUInteger count = [_iconTitleStack count];
    if (count > 0) {
        // pop icon title
        [self setSessionName:[_iconTitleStack objectAtIndex:count - 1]];
        [_iconTitleStack removeObjectAtIndex:count - 1];
    }
}

#pragma mark - Private

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

- (void)updateCachedEvaluatedTitleFormatIfNeeded {
    if (_cachedEvaluatedTitleFormat && !_cachedEvaluatedTitleFormatInvalid) {
        return;
    }
    if (!_cachedEvaluatedTitleFormat) {
        [self updateCachedEvaluatedTitleFormatSynchronously:YES];
    }
    [self updateCachedEvaluatedTitleFormatSynchronously:NO];
}

- (void)updateCachedEvaluatedTitleFormatSynchronously:(BOOL)synchronous {
    __weak __typeof(self) weakSelf = self;
    [self evaluatePresentationNameSynchronously:synchronous completion:^(NSString *presentationName) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            if ([NSObject object:strongSelf->_cachedEvaluatedTitleFormat isEqualToObject:presentationName]) {
                return;
            }
            strongSelf->_cachedEvaluatedTitleFormat = [presentationName copy];
            if (!synchronous) {
                [strongSelf.delegate sessionNameControllerPresentationNameDidChangeTo:presentationName];
            }
        }
    }];
}

@end

