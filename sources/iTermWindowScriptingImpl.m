@implementation THE_CLASS (Scripting)

- (NSScriptObjectSpecifier *)objectSpecifier {
    NSUInteger anIndex = 0;
    id classDescription = nil;

    NSScriptObjectSpecifier *containerRef;

    NSArray<iTermScriptingWindow *> *windows = [[iTermApplication sharedApplication] orderedScriptingWindows];
    anIndex = [windows indexOfObjectPassingTest:^BOOL(iTermScriptingWindow * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.underlyingWindow == self;
    }];
    if (anIndex != NSNotFound) {
        containerRef = [NSApp objectSpecifier];
        classDescription = [NSClassDescription classDescriptionForClass:[NSApp class]];
        return [[[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:classDescription
                                                            containerSpecifier:containerRef
                                                                           key:@"orderedScriptingWindows"
                                                                      uniqueID:@([self windowNumber])] autorelease];
    } else {
        return nil;
    }
}

#pragma mark - Handlers for commands

- (id)handleSelectCommand:(NSScriptCommand *)command {
    [[iTermController sharedInstance] setCurrentTerminal:_delegate];
    return nil;
}

- (id)handleCloseScriptCommand:(NSScriptCommand *)command {
    [self performClose:nil];
    return nil;
}

- (id)handleCreateTabWithDefaultProfileCommand:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *command = args[@"command"];
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    PTYSession *session =
        [[iTermController sharedInstance] launchBookmark:profile
                                              inTerminal:_delegate
                                                 withURL:nil
                                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                 makeKey:YES
                                             canActivate:NO
                                                 command:command
                                                   block:nil];
    return [_delegate tabForSession:session];
}

- (id)handleCreateTabCommand:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *command = args[@"command"];
    NSString *profileName = args[@"profile"];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (!profile) {
        [scriptCommand setScriptErrorNumber:1];
        [scriptCommand setScriptErrorString:[NSString stringWithFormat:@"No profile exists named '%@'",
                                             profileName]];
        return nil;
    }
    PTYSession *session =
        [[iTermController sharedInstance] launchBookmark:profile
                                              inTerminal:_delegate
                                                 withURL:nil
                                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                 makeKey:YES
                                             canActivate:NO
                                                 command:command
                                                   block:nil];
    return [_delegate tabForSession:session];
}

- (id)handleRevealHotkeyWindowCommand:(NSScriptCommand *)scriptCommand {
    [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:_delegate] revealForScripting];
    return nil;
}

- (id)handleHideHotkeyWindowCommand:(NSScriptCommand *)scriptCommand {
    [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:_delegate] hideForScripting];
    return nil;
}

- (id)handleToggleHotkeyWindowCommand:(NSScriptCommand *)scriptCommand {
    [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:_delegate] toggleForScripting];
    return nil;
}

#pragma mark - Accessors

- (NSArray *)tabs {
    return [_delegate tabs];
}

- (void)setTabs:(NSArray *)tabs {
}

#pragma mark NSScriptKeyValueCoding for to-many relationships
// (See NSScriptKeyValueCoding.h)

- (NSUInteger)count {
    return 1;
}

- (NSUInteger)countOfTabs {
    return [[_delegate tabs] count];
}

- (id)valueInTabsAtIndex:(unsigned)anIndex {
    return [_delegate tabs][anIndex];
}

- (void)replaceInTabs:(PTYTab *)replacementTab atIndex:(unsigned)anIndex {
    [_delegate insertInTabs:replacementTab atIndex:anIndex];
    [_delegate closeTab:[_delegate tabs][anIndex + 1]];
}

- (void)insertInTabs:(PTYTab *)tab atIndex:(unsigned)anIndex {
    [_delegate insertTab:tab atIndex:anIndex];
}

- (void)removeFromTabsAtIndex:(unsigned)anIndex {
    NSArray *tabs = [_delegate tabs];
    [_delegate closeTab:tabs[anIndex]];
}


- (PTYTab *)currentTab {
    return [_delegate currentTab];
}

- (PTYSession *)currentSession {
    return [_delegate currentSession];
}

- (BOOL)isHotkeyWindow {
    return [_delegate isHotKeyWindow];
}

- (NSString *)hotkeyWindowProfile {
    if ([_delegate isHotKeyWindow]) {
        return [[[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:_delegate] profile] objectForKey:KEY_NAME];
    } else {
        return nil;
    }
}



@end
