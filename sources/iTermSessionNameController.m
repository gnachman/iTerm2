//
//  iTermSessionNameController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/18.
//

#import "iTermSessionNameController.h"

#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"

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
        [components addObject:@"\(session.job.name)"];
    }
    if (titleComponents & iTermTitleComponentsWorkingDirectory) {
        [components addObject:@"\(session.path)"];
    }
    if (titleComponents & iTermTitleComponentsTTY) {
        [components addObject:@"\(session.tty)"];
    }

    return [components componentsJoinedByString:@" — "];
}

- (instancetype)initWithProfileName:(NSString *)profileName
                        titleFormat:(NSString *)titleFormat {
    self = [super init];
    if (self) {
        _firstSessionName = [profileName copy];
        _sessionName = [profileName copy];
        _originalName = [profileName copy];
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
                    legacyOriginalName:(NSString *)legacyOriginalName
                     legacyWindowTitle:(NSString *)legacyWindowTitle {
    if (state) {
#warning TODO
    } else {
        _profileName = [legacyProfileName copy];
        if (legacyName) {
            [self setSessionName:legacyName];
        }
        if (legacyOriginalName) {
            [self setOriginalName:legacyOriginalName];
        }
        if (legacyWindowTitle) {
            [self setWindowTitle:legacyWindowTitle];
        }
    }
    [self.delegate sessionNameControllerDidChangeWindowTitle];
}

- (void)didInitializeSessionWithName:(NSString *)newName {
    [self setOriginalName:newName];
    [self setSessionName:newName];
}

- (void)profileDidChangeToProfileWithName:(NSString *)newName {
    BOOL originalNameEqualedOldProfileName = [self.originalName isEqualToString:_profileName];
    BOOL sessionNameEqualedOldProfileName = [self.sessionName isEqualToString:_profileName];
    if (originalNameEqualedOldProfileName) {
        [self setOriginalName:newName.copy];
    }
    if (sessionNameEqualedOldProfileName) {
        [self setSessionName:newName.copy];
    }
    _profileName = [newName copy];
}

- (void)profileNameDidChangeTo:(NSString *)newName {
    // Set name, which overrides any session-set icon name.
    [self setSessionName:newName.copy];
    // set default name, which will appear as a prefix if the session changes the name.
    [self setOriginalName:newName.copy];
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
    [self setOriginalName:real.originalName];
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
    [self evaluatePresentationName:^(NSString *presentationName) {
        [weakSelf.delegate sessionNameControllerPresentationNameDidChangeTo:presentationName];
    }];
}

- (void)evaluatePresentationName:(void (^)(NSString *presentationName))completion {
#warning TODO: use iTermEval here.
    completion(self.presentationName);
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
    return [self formattedName:_sessionName];
}

- (void)setOriginalName:(NSString *)theName {
    if ([_originalName isEqualToString:theName]) {
        return;
    }

    if (_originalName) {
        // Clear the window title if it is not different. This is super subtle and hacky. When the
        // session name gets changed then the window title is also changed if it was nil. Then this
        // gets called if it was a manual (Edit Session) change. This sees that they're equal and
        // resets the windowTitle. Uh what?
        if (self.windowTitle == nil || [self.sessionName isEqualToString:self.windowTitle]) {
            _windowTitle = nil;
        }
        _originalName = nil;
    }
    if (!theName) {
        theName = @"Untitled";
    }

    _originalName = [theName copy];
}

- (NSString *)presentationOriginalName {
    return [self formattedName:self.originalName];
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

- (NSString *)formattedName:(NSString*)base {
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

    // This is a horrible hack. When the session name equals its first-ever value then we do special
    // stuff.
    BOOL baseEqualsFirstSessionName = [base isEqualToString:self.firstSessionName];
    if (descriptor.shouldShowJobName && descriptor.jobName) {
        if (baseEqualsFirstSessionName && !descriptor.shouldShowProfileName) {
            // SPECIAL STUFF: Exclude the "base" name. This is crazytimes because the base name could be the window title, which is settable by escape sequence.
            return [NSString stringWithFormat:@"%@", descriptor.jobName];
        } else {
            return [NSString stringWithFormat:@"%@ (%@)", base, descriptor.jobName];
        }
    } else {
        if (baseEqualsFirstSessionName && !descriptor.shouldShowProfileName) {
            // SPECIAL STUFF: Don't show the base name at all. This is just wrong if the base name is the window title.
            return @"Shell";
        } else {
            return base;
        }
    }
}

@end

