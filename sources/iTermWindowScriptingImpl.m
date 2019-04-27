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
    [[iTermController sharedInstance] setCurrentTerminal:(PseudoTerminal *)self.ptyDelegate];
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
                                              inTerminal:(PseudoTerminal *)self.ptyDelegate
                                                 withURL:nil
                                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                 makeKey:YES
                                             canActivate:NO
                                                 command:command
                                                   block:nil
                                             synchronous:YES
                                              completion:nil];
    return [self.ptyDelegate tabForSession:session];
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
                                              inTerminal:(PseudoTerminal *)self.ptyDelegate
                                                 withURL:nil
                                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                 makeKey:YES
                                             canActivate:NO
                                                 command:command
                                                   block:nil
                                             synchronous:YES
                                              completion:nil];
    return [self.ptyDelegate tabForSession:session];
}

- (id)handleRevealHotkeyWindowCommand:(NSScriptCommand *)scriptCommand {
    [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:(PseudoTerminal *)self.ptyDelegate] revealForScripting];
    return nil;
}

- (id)handleHideHotkeyWindowCommand:(NSScriptCommand *)scriptCommand {
    [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:(PseudoTerminal *)self.ptyDelegate] hideForScripting];
    return nil;
}

- (id)handleToggleHotkeyWindowCommand:(NSScriptCommand *)scriptCommand {
    [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:(PseudoTerminal *)self.ptyDelegate] toggleForScripting];
    return nil;
}

#pragma mark - Accessors

- (NSArray *)tabs {
    return [(PseudoTerminal *)self.ptyDelegate tabs];
}

- (void)setTabs:(NSArray *)tabs {
}

#pragma mark NSScriptKeyValueCoding for to-many relationships
// (See NSScriptKeyValueCoding.h)

- (NSUInteger)count {
    return 1;
}

- (NSUInteger)countOfTabs {
    return [[(PseudoTerminal *)self.ptyDelegate tabs] count];
}

- (id)valueInTabsAtIndex:(unsigned)anIndex {
    return [(PseudoTerminal *)self.ptyDelegate tabs][anIndex];
}

- (void)replaceInTabs:(PTYTab *)replacementTab atIndex:(unsigned)anIndex {
    [self insertInTabs:replacementTab atIndex:anIndex];
    [(PseudoTerminal *)self.ptyDelegate closeTab:[(PseudoTerminal *)self.ptyDelegate tabs][anIndex + 1]];
}

- (void)insertInTabs:(PTYTab *)tab atIndex:(unsigned)anIndex {
    [(PseudoTerminal *)self.ptyDelegate insertTab:tab atIndex:anIndex];
}

- (void)removeFromTabsAtIndex:(unsigned)anIndex {
    NSArray *tabs = [(PseudoTerminal *)self.ptyDelegate tabs];
    [(PseudoTerminal *)self.ptyDelegate closeTab:tabs[anIndex]];
}


- (PTYTab *)currentTab {
    return [(PseudoTerminal *)self.ptyDelegate currentTab];
}

- (PTYSession *)currentSession {
    return [(PseudoTerminal *)self.ptyDelegate currentSession];
}

- (BOOL)isHotkeyWindow {
    return [(PseudoTerminal *)self.ptyDelegate isHotKeyWindow];
}

- (NSString *)hotkeyWindowProfile {
    if ([(PseudoTerminal *)self.ptyDelegate isHotKeyWindow]) {
        return [[[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:(PseudoTerminal *)self.ptyDelegate] profile] objectForKey:KEY_NAME];
    } else {
        return nil;
    }
}

- (BOOL)scriptFrontmost {
    return [[[iTermController sharedInstance] currentTerminal] window] == self;
}

@end
