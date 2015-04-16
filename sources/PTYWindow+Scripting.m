#import "PTYWindow+Scripting.h"
#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermController.h"
#import "PTYTab.h"

@implementation PTYWindow (Scripting)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier {
    NSUInteger anIndex = 0;
    id classDescription = nil;

    NSScriptObjectSpecifier *containerRef;

    NSArray *windows = [[iTermApplication sharedApplication] orderedWindows];
    anIndex = [windows indexOfObjectIdenticalTo:self];
    if (anIndex != NSNotFound) {
        containerRef = [NSApp objectSpecifier];
        classDescription = [NSClassDescription classDescriptionForClass:[NSApp class]];
        // Create and return the specifier
        return [[[NSIndexSpecifier alloc]
                   initWithContainerClassDescription:classDescription
                                  containerSpecifier:containerRef
                                                 key:@"windows"
                                               index:anIndex] autorelease];
    } else {
        return nil;
    }
}

#pragma mark - Handlers for commands

- (id)handleSelectCommand:(NSScriptCommand *)command {
    [[iTermController sharedInstance] setCurrentTerminal:_delegate];
    return nil;
}

- (id)handleLaunchScriptCommand:(NSScriptCommand *)command {
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    NSString *session = [args objectForKey:@"session"];
    NSDictionary *abEntry;

    abEntry = [[ProfileModel sharedInstance] bookmarkWithName:session];
    if (abEntry == nil) {
        abEntry = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (abEntry == nil) {
        NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        [aDict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        abEntry = aDict;
    }

    return [[iTermController sharedInstance] launchBookmark:abEntry inTerminal:_delegate];
}

- (id)handleCloseScriptCommand:(NSScriptCommand *)command {
    [self performClose:nil];
    return nil;
}

- (void)handleSplitScriptCommand:(NSScriptCommand *)command {
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    NSString *direction = args[@"direction"];
    BOOL isVertical = [direction isEqualToString:@"vertical"];
    NSString *profileName = args[@"profile"];
    NSDictionary *abEntry;

    abEntry = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (abEntry == nil) {
        abEntry = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (abEntry == nil) {
        NSMutableDictionary* aDict = [NSMutableDictionary dictionary];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        [aDict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        abEntry = aDict;
    }

    [_delegate splitVertically:isVertical
                  withBookmark:abEntry
                 targetSession:[[_delegate currentTab] activeSession]];
}

- (void)handleCreateTabWithDefaultProfileCommand:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *command = args[@"command"];
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    [[iTermController sharedInstance] launchBookmark:profile
                                          inTerminal:_delegate
                                             withURL:nil
                                            isHotkey:NO
                                             makeKey:YES
                                             command:command];
}

- (void)handleCreateTabCommand:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *command = args[@"command"];
    NSString *profileName = args[@"profile"];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (!profile) {
        [scriptCommand setScriptErrorNumber:1];
        [scriptCommand setScriptErrorString:[NSString stringWithFormat:@"No profile exists named '%@'",
                                             profileName]];
        return;
    }
    [[iTermController sharedInstance] launchBookmark:profile
                                          inTerminal:_delegate
                                             withURL:nil
                                            isHotkey:NO
                                             makeKey:YES
                                             command:command];
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

@end
