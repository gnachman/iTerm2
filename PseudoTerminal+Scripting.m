#import "PseudoTerminal+Scripting.h"
#import "DebugLogging.h"
#import "iTermController.h"
#import "PTYTab.h"

// keys for attributes:
static NSString *const kColumnsKVCKey = @"columns";
static NSString *const kRowsKVCKey = @"rows";
// keys for to-many relationships:
static NSString *const kTabsKVCKey = @"tabs";

@implementation PseudoTerminal (Scripting)

// a class method to provide the keys for KVC:
+ (NSArray*)kvcKeys {
    static NSArray *_kvcKeys = nil;
    if (nil == _kvcKeys ){
        _kvcKeys = [[NSArray alloc] initWithObjects:
            kColumnsKVCKey, kRowsKVCKey, kTabsKVCKey, nil ];
    }
    return _kvcKeys;
}

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier {
    NSUInteger anIndex = 0;
    id classDescription = nil;

    NSScriptObjectSpecifier *containerRef;

    NSArray *terminals = [[iTermController sharedInstance] terminals];
    anIndex = [terminals indexOfObjectIdenticalTo:self];
    if (anIndex != NSNotFound) {
        containerRef = [NSApp objectSpecifier];
        classDescription = [NSClassDescription classDescriptionForClass:[NSApp class]];
        //create and return the specifier
        return [[[NSIndexSpecifier alloc]
                   initWithContainerClassDescription:classDescription
                                  containerSpecifier:containerRef
                                                 key:@"terminals"
                                               index:anIndex] autorelease];
    } else {
        return nil;
    }
}

#pragma mark - Handlers for commands

- (id)handleSelectCommand:(NSScriptCommand *)command {
    [[iTermController sharedInstance] setCurrentTerminal:self];
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

    return [[iTermController sharedInstance] launchBookmark:abEntry inTerminal:self];
}

- (id)handleCloseCommand:(NSScriptCommand *)command {
    [[self window] performClose:nil];
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

    [self splitVertically:isVertical
             withBookmark:abEntry
            targetSession:[[self currentTab] activeSession]];

}

- (void)handleCreateTabWithDefaultProfileCommand:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *command = args[@"command"];
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    [[iTermController sharedInstance] launchBookmark:profile
                                          inTerminal:self
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
                                          inTerminal:self
                                             withURL:nil
                                            isHotkey:NO
                                             makeKey:YES
                                             command:command];
}

#pragma mark - Accessors

// -tabs is defined in PseudoTerminal.m

- (void)setTabs:(NSArray *)tabs {
}

#pragma mark NSScriptKeyValueCoding for to-many relationships
// (See NSScriptKeyValueCoding.h)

- (NSUInteger)count {
    return 1;
}

- (NSUInteger)countOfTabs {
    return [[self tabs] count];
}

- (id)valueInTabsAtIndex:(unsigned)anIndex {
    return [self tabs][anIndex];
}

- (void)replaceInTabs:(PTYTab *)replacementTab atIndex:(unsigned)anIndex {
    [self insertInTabs:replacementTab atIndex:anIndex];
    [self closeTab:[self tabs][anIndex + 1]];
}

- (void)insertInTabs:(PTYTab *)tab atIndex:(unsigned)anIndex {
    [self insertTab:tab atIndex:anIndex];
}

- (void)removeFromTabsAtIndex:(unsigned)anIndex {
    NSArray *tabs = [self tabs];
    [self closeTab:tabs[anIndex]];
}

- (id)valueForKey:(NSString *)key {
    if ([key isEqualToString:@"currentTab"]) {
        return [self currentTab];
    } else if ([key isEqualToString:@"currentSession"]) {
        return [self currentSession];
    } else if ([key isEqualToString:@"tabs"]) {
        return [self tabs];
    } else {
        return nil;
    }
}

@end
