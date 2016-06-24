#import "iTermHotKeyProfileBindingController.h"

#import "ITAddressBookMgr.h"
#import "iTermHotKeyController.h"
#import "iTermProfileHotKey.h"
#import "iTermProfilePreferences.h"
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
            [self registerHotKeyForProfile:profile];
        } else if (!hasHotKey && _guidToHotKeyMap[guid]) {
            [self unregisterHotKeyForProfileWithGuid:guid];
        } else if (hasHotKey && _guidToHotKeyMap[guid]) {
            [self updateRegistrationForProfile:profile];
        }
    }
    
    for (NSString *guid in guidsOfProfileHotKeys) {
        [self unregisterHotKeyForProfileWithGuid:guid];
    }
}

#pragma mark - Private

- (void)registerHotKeyForProfile:(Profile *)profile {
    NSString *guid = [iTermProfilePreferences stringForKey:KEY_GUID inProfile:profile];
    NSLog(@"Register hotkey for guid %@", guid);
    NSUInteger keyCode = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE inProfile:profile];
    NSEventModifierFlags modifiers = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_FLAGS inProfile:profile];
    NSString *characters = [iTermProfilePreferences stringForKey:KEY_HOTKEY_CHARACTERS inProfile:profile];
    NSString *charactersIgnoringModifiers = [iTermProfilePreferences stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS inProfile:profile];
    iTermProfileHotKey *hotKey = [[[iTermProfileHotKey alloc] initWithKeyCode:keyCode
                                                                    modifiers:modifiers
                                                                   characters:characters
                                                  charactersIgnoringModifiers:charactersIgnoringModifiers
                                                                      profile:profile] autorelease];
    NSLog(@"Registered %@", hotKey);
    _guidToHotKeyMap[guid] = hotKey;
    [[iTermHotKeyController sharedInstance] addHotKey:hotKey];
}

- (void)unregisterHotKeyForProfileWithGuid:(NSString *)guid {
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
    NSUInteger keyCode = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE inProfile:profile];
    NSString *charactersIgnoringModifiers = [iTermProfilePreferences stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS inProfile:profile];
    NSEventModifierFlags modifiers = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_FLAGS inProfile:profile];
    iTermProfileHotKey *hotKey = _guidToHotKeyMap[guid];

    // It's important to detect changes to charactersIgnoringModifiers because if it's not up-to-date
    // in the carbon hotkey then keypresses while a shortcut input field is first responder will send
    // the wrong 'characters' field to it.
    if (hotKey.keyCode == keyCode &&
        hotKey.modifiers == modifiers &&
        [hotKey.charactersIgnoringModifiers isEqualToString:charactersIgnoringModifiers]) {
        // No change
        return;
    }

    // Update the keycode and modifier and re-register.
    NSLog(@"Update registration for %@", hotKey);
    [hotKey unregister];
    hotKey.keyCode = keyCode;
    hotKey.charactersIgnoringModifiers = charactersIgnoringModifiers;
    hotKey.modifiers = modifiers;
    [hotKey register];
}

#pragma mark - Notifications

- (void)reloadProfiles:(NSNotification *)notification {
    [self refresh];
}

@end
