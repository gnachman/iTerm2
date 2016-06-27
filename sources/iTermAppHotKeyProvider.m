#import "iTermAppHotKeyProvider.h"

#import "iTermAppHotKey.h"
#import "iTermHotKeyController.h"
#import "iTermPreferences.h"
#import "iTermShortcut.h"

@interface iTermAppHotKeyProvider()
@property(nonatomic, retain) iTermAppHotKey *appHotKey;
@end

@implementation iTermAppHotKeyProvider

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self invalidate];
    }
    return self;
}

- (void)invalidate {
    if (self.appHotKey) {
        [[iTermHotKeyController sharedInstance] removeHotKey:self.appHotKey];
    }

    // TODO: Migrate deprecated prefs and use new ones here.
    if ([iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled]) {
        NSEventModifierFlags modifiers = [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
        NSUInteger code = [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
        unichar character = [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
        NSString *characters = [NSString stringWithFormat:@"%C", character];
        
        iTermShortcut *shortcut = [[[iTermShortcut alloc] initWithKeyCode:code
                                                                modifiers:modifiers
                                                               characters:characters
                                              charactersIgnoringModifiers:characters] autorelease];
        self.appHotKey = [[[iTermAppHotKey alloc] initWithShortcuts:@[ shortcut ]
                                              hasModifierActivation:NO
                                                 modifierActivation:0] autorelease];
        
        [[iTermHotKeyController sharedInstance] addHotKey:self.appHotKey];
    } else {
        self.appHotKey = nil;
    }
}

@end
