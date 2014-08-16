#import "PseudoTerminal+Scripting.h"
#import "DebugLogging.h"
#import "iTermController.h"
#import "PTYTab.h"

// keys for attributes:
static NSString *const kColumnsKVCKey = @"columns";
static NSString *const kRowsKVCKey = @"rows";
// keys for to-many relationships:
static NSString *const kSessionsKVCKey = @"sessions";

@implementation PseudoTerminal (Scripting)

// a class method to provide the keys for KVC:
+ (NSArray*)kvcKeys {
    static NSArray *_kvcKeys = nil;
    if (nil == _kvcKeys ){
        _kvcKeys = [[NSArray alloc] initWithObjects:
            kColumnsKVCKey, kRowsKVCKey, kSessionsKVCKey, nil ];
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

- (void)handleSelectScriptCommand:(NSScriptCommand *)command {
    [[iTermController sharedInstance] setCurrentTerminal: self];
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

#pragma mark - Accessors

// This is kept around because it's used by applescript but it only returns the active session
// in each tab. Use -allSessions if you want them all. This is for backward compatibility. For a
// while it did return all sessions but that caused bug 3147.
- (NSArray *)sessions {
    NSMutableArray *sessions = [NSMutableArray array];

    for (PTYTab *tab in [self tabs]) {
        [sessions addObject:tab.activeSession];
    }

    return sessions;
}

- (void)setSessions:(NSArray*)sessions {
}

#pragma mark NSScriptKeyValueCoding for to-many relationships
// (See NSScriptKeyValueCoding.h)

- (id)valueInSessionsAtIndex:(unsigned)anIndex {
    PTYTab *tab = [self tabs][anIndex];
    return [tab activeSession];
}

- (id)valueWithName:(NSString *)uniqueName inPropertyWithKey:(NSString *)propertyKey {
    if ([propertyKey isEqualToString:kSessionsKVCKey]) {
        for (PTYTab *tab in [self tabs]) {
            PTYSession *aSession = tab.activeSession;
            if ([aSession.name isEqualToString:uniqueName]) {
                return aSession;
            }
        }
    }

    return nil;
}

// The 'uniqueID' argument might be an NSString or an NSNumber.
- (id)valueWithID:(NSString *)uniqueID inPropertyWithKey:(NSString*)propertyKey {
    if ([propertyKey isEqualToString:kSessionsKVCKey]) {
        for (PTYTab *tab in [self tabs]) {
            PTYSession *aSession = tab.activeSession;
            if ([aSession.tty isEqualToString:uniqueID]) {
                return aSession;
            }
        }
    }
    return nil;
}

- (void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)anIndex {
    DLog(@"PseudoTerminal: -replaceInSessions: %p atIndex: %d", object, anIndex);
    // TODO: Test this
    [self setupSession:object title:nil withSize:nil];
    if ([object screen]) {  // screen initialized ok
        [self replaceSession:object atIndex:anIndex];
    }
}

- (void)insertInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    DLog(@"PseudoTerminal: -insertInSessions: %p atIndex: %d", object, anIndex);
    BOOL toggle = NO;
    if (![self windowInitialized]) {
        Profile *aDict = [object profile];
        [self finishInitializationWithSmartLayout:YES
                                       windowType:[[iTermController sharedInstance] windowTypeForBookmark:aDict]
                                  savedWindowType:WINDOW_TYPE_NORMAL
                                           screen:aDict[KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1
                                         isHotkey:NO];
        if ([[aDict objectForKey:KEY_HIDE_AFTER_OPENING] boolValue]) {
            [self hideAfterOpening];
        }
        [[iTermController sharedInstance] addInTerminals:self];
        toggle = ([self windowType] == WINDOW_TYPE_LION_FULL_SCREEN);
    }

    [self setupSession:object title:nil withSize:nil];
    if ([object screen]) {  // screen initialized ok
        [self insertSession:object atIndex:anIndex];
    }
    [[self currentTab] numberOfSessionsDidChange];
    if (toggle) {
        [self delayedEnterFullscreen];
    }
}

- (void)removeFromSessionsAtIndex:(unsigned)anIndex {
    NSArray *tabs = [self tabs];
    if (anIndex < tabs.count) {
        PTYSession *aSession = [tabs[anIndex] activeSession];
        [self closeSession:aSession];
    }
}

@end
