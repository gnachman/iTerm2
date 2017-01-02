#import "iTermHotKeyProfileBindingController.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermHotKeyController.h"
#import "iTermProfileHotKey.h"
#import "iTermProfilePreferences.h"
#import "iTermShortcut.h"
#import "NSArray+iTerm.h"
#import "ProfileModel.h"

@implementation iTermHotKeyProfileBindingController {
    NSMutableDictionary<NSString *, iTermProfileHotKey *> *_guidToHotKeyMap;
}

+ (iTermHotKeyProfileBindingController *)sharedInstance {
    static iTermHotKeyProfileBindingController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _guidToHotKeyMap = [[NSMutableDictionary alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadProfiles:)
                                                     name:kReloadAllProfiles
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadProfiles:)
                                                     name:kReloadAddressBookNotification
                                                   object:nil];
        [self refresh];
    }
    return self;
}

- (void)refresh {
    NSMutableSet<NSString *> *guidsOfProfileHotKeys = [NSMutableSet setWithArray:[_guidToHotKeyMap allKeys]];

    for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
        NSString *guid = [iTermProfilePreferences stringForKey:KEY_GUID inProfile:profile];
        [guidsOfProfileHotKeys removeObject:guid];
        const BOOL hasHotKey = [iTermProfilePreferences boolForKey:KEY_HAS_HOTKEY inProfile:profile];
        
        // Unregister. If the key has changed, we'll re-register. If the profile no longer has a hotkey
        // it will stay unregistered.
        if (hasHotKey && !_guidToHotKeyMap[guid]) {
            [self registerHotKeysForProfile:profile];
        } else if (!hasHotKey && _guidToHotKeyMap[guid]) {
            [self unregisterHotKeysForProfileWithGuid:guid];
        } else if (hasHotKey && _guidToHotKeyMap[guid]) {
            [self updateRegistrationForProfile:profile];
        }
    }
    
    for (NSString *guid in guidsOfProfileHotKeys) {
        [self unregisterHotKeysForProfileWithGuid:guid];
    }
}

#pragma mark - Private

- (void)registerHotKeysForProfile:(Profile *)profile {
    NSString *guid = [iTermProfilePreferences stringForKey:KEY_GUID inProfile:profile];
    DLog(@"Register hotkey for guid %@ (%@)", guid, profile[KEY_NAME]);
    
    BOOL hasModifierActivation = [iTermProfilePreferences boolForKey:KEY_HOTKEY_ACTIVATE_WITH_MODIFIER inProfile:profile];
    iTermHotKeyModifierActivation modifierActivation = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_ACTIVATION inProfile:profile];
    NSArray<iTermShortcut *> *shortcuts = [[iTermShortcut shortcutsForProfile:profile] filteredArrayUsingBlock:^BOOL(iTermShortcut *anObject) {
        return anObject.isAssigned;
    }];
    if (!shortcuts.count) {
        DLog(@"None of the shortcuts in profile %@ are assigned", profile[KEY_NAME]);
        return;
    }
    
    iTermProfileHotKey *hotKey =
        [[[iTermProfileHotKey alloc] initWithShortcuts:shortcuts
                                 hasModifierActivation:hasModifierActivation
                                    modifierActivation:modifierActivation
                                               profile:profile] autorelease];
    DLog(@"Registered %@", hotKey);
    _guidToHotKeyMap[guid] = hotKey;
    [[iTermHotKeyController sharedInstance] addHotKey:hotKey];
}

- (void)unregisterHotKeysForProfileWithGuid:(NSString *)guid {
    NSLog(@"Unregister for guid %@", guid);
    iTermProfileHotKey *hotKey = _guidToHotKeyMap[guid];
    if (hotKey) {
        NSLog(@"Unregistering %@", hotKey);
        [[iTermHotKeyController sharedInstance] removeHotKey:hotKey];
        [_guidToHotKeyMap removeObjectForKey:guid];
    }
}

- (void)updateRegistrationForProfile:(Profile *)profile {
    NSString *guid = [iTermProfilePreferences stringForKey:KEY_GUID inProfile:profile];
    iTermProfileHotKey *hotKey = _guidToHotKeyMap[guid];
    BOOL hasModifierActivation = [iTermProfilePreferences boolForKey:KEY_HOTKEY_ACTIVATE_WITH_MODIFIER inProfile:profile];
    iTermHotKeyModifierActivation modifierActivation = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_ACTIVATION inProfile:profile];

    // Update the keycode and modifier and re-register.
    DLog(@"Update registration for %@", hotKey);
    [hotKey setShortcuts:[iTermShortcut shortcutsForProfile:profile]
        hasModifierActivation:hasModifierActivation
           modifierActivation:modifierActivation];
}

#pragma mark - Notifications

- (void)reloadProfiles:(NSNotification *)notification {
    [self refresh];
}

@end
