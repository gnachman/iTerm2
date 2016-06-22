#import "iTermBaseHotKey.h"

#import "iTermApplicationDelegate.h"
#import "iTermCarbonHotKeyController.h"

const NSEventModifierFlags kHotKeyModifierMask = (NSCommandKeyMask |
                                                  NSAlternateKeyMask |
                                                  NSShiftKeyMask |
                                                  NSControlKeyMask);

@interface iTermBaseHotKey()

// Override this to do a thing that needs to be done.
- (void)hotKeyPressed;

@end

@implementation iTermBaseHotKey {
    // The registered carbon hotkey that listens for hotkey presses.
    iTermHotKey *_carbonHotKey;
}

- (instancetype)initWithKeyCode:(NSUInteger)keyCode
                      modifiers:(NSEventModifierFlags)modifiers
                     characters:(NSString *)characters
    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers {
    self = [super init];
    if (self) {
        _keyCode = keyCode;
        _modifiers = modifiers & kHotKeyModifierMask;
        _characters = [characters copy];
        _charactersIgnoringModifiers = [charactersIgnoringModifiers copy];
    }
    return self;
}

- (void)dealloc {
    [_characters release];
    [_charactersIgnoringModifiers release];
    [super dealloc];
}

- (BOOL)keyDownEventTriggers:(NSEvent *)event {
    return (([event modifierFlags] & kHotKeyModifierMask) == (_modifiers & kHotKeyModifierMask) &&
            [event keyCode] == _keyCode);
}

- (void)register {
    if (_carbonHotKey) {
        [self unregister];
    }

    _carbonHotKey =
        [[[iTermCarbonHotKeyController sharedInstance] registerKeyCode:_keyCode
                                                             modifiers:_modifiers
                                                            characters:_characters
                                           charactersIgnoringModifiers:_charactersIgnoringModifiers
                                                                target:self
                                                              selector:@selector(carbonHotkeyPressed:)
                                                              userData:nil] retain];

}

- (void)unregister {
    if (_carbonHotKey) {
        [[iTermCarbonHotKeyController sharedInstance] unregisterHotKey:_carbonHotKey];
        [_carbonHotKey release];
        _carbonHotKey = nil;
    }
}

- (void)simulatePress {
    [self carbonHotkeyPressed:nil];
}

- (void)hotKeyPressed {
    [NSException raise:NSInternalInconsistencyException format:@"Not implemented. Use a subclass."];
}

#pragma mark - Actions

- (void)carbonHotkeyPressed:(NSDictionary *)userInfo {
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        return;
    }
    
    [self hotKeyPressed];
}

@end
