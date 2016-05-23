#import "iTermAppHotKeyProvider.h"

#import "iTermAppHotKey.h"
#import "iTermHotKeyController.h"
#import "iTermPreferences.h"

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
        self.appHotKey = [[iTermAppHotKey alloc] initWithKeyCode:code modifiers:modifiers];
        [[iTermHotKeyController sharedInstance] addHotKey:self.appHotKey];
    } else {
        self.appHotKey = nil;
    }
}

@end
