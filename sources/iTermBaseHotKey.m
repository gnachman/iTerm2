#import "iTermBaseHotKey.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermEventTap.h"
#import "NSArray+iTerm.h"

static const CGEventFlags kCGEventHotKeyModifierMask = (kCGEventFlagMaskAlphaShift |
                                                        kCGEventFlagMaskAlternate |
                                                        kCGEventFlagMaskCommand |
                                                        kCGEventFlagMaskControl);

const NSEventModifierFlags kHotKeyModifierMask = (NSCommandKeyMask |
                                                  NSAlternateKeyMask |
                                                  NSShiftKeyMask |
                                                  NSControlKeyMask);

@interface iTermBaseHotKey()<iTermEventTapObserver>

// Override this to do a thing that needs to be done. `siblings` are other hotkeys (besides the one
// this call was made for) that have the same keypress.
- (void)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)siblings;

@end

@implementation iTermBaseHotKey {
    // The registered carbon hotkey that listens for hotkey presses.
    iTermHotKey *_carbonHotKey;
    BOOL _observingEventTap;
    NSTimeInterval _lastModifierTapTime;
    BOOL _modifierWasPressed;
}

- (instancetype)initWithKeyCode:(NSUInteger)keyCode
                      modifiers:(NSEventModifierFlags)modifiers
                     characters:(NSString *)characters
    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
          hasModifierActivation:(BOOL)hasModifierActivation
             modifierActivation:(iTermHotKeyModifierActivation)modifierActivation {
    self = [super init];
    if (self) {
        _keyCode = keyCode;
        _modifiers = modifiers & kHotKeyModifierMask;
        _characters = [characters copy];
        _charactersIgnoringModifiers = [charactersIgnoringModifiers copy];
        _hasModifierActivation = hasModifierActivation;
        _modifierActivation = modifierActivation;
    }
    return self;
}

ITERM_WEAKLY_REFERENCEABLE

- (void)iterm_dealloc {
    [_characters release];
    [_charactersIgnoringModifiers release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p keyCode=%@ modifiers=%@ charactersIgnoringModifiers=“%@”>",
            NSStringFromClass([self class]), self, @(_keyCode), @(_modifiers), _charactersIgnoringModifiers];
}

- (iTermHotKeyDescriptor *)hotKeyDescriptor {
    return [iTermHotKeyDescriptor descriptorWithKeyCode:self.keyCode
                                              modifiers:(self.modifiers & kCarbonHotKeyModifiersMask)];
}

- (iTermHotKeyDescriptor *)modifierActivationDescriptor {
    if (self.hasModifierActivation) {
        return [iTermHotKeyDescriptor descriptorWithModifierActivation:self.modifierActivation];
    } else {
        return nil;
    }
}

- (BOOL)keyDownEventTriggers:(NSEvent *)event {
    return (([event modifierFlags] & kHotKeyModifierMask) == (_modifiers & kHotKeyModifierMask) &&
            [event keyCode] == _keyCode);
}

- (void)register {
    if (_charactersIgnoringModifiers.length) {
        if (_carbonHotKey) {
            [self unregisterCarbonHotKey];
        }

        _carbonHotKey =
            [[[iTermCarbonHotKeyController sharedInstance] registerKeyCode:_keyCode
                                                                 modifiers:_modifiers
                                                                characters:_characters
                                               charactersIgnoringModifiers:_charactersIgnoringModifiers
                                                                    target:self
                                                                  selector:@selector(carbonHotkeyPressed:siblings:)
                                                                  userData:nil] retain];
    }

    if (_hasModifierActivation && !_observingEventTap) {
        [[iTermEventTap sharedInstance] addObserver:self];
    }
}

- (void)unregister {
    if (_carbonHotKey) {
        [self unregisterCarbonHotKey];
    }
    if (_observingEventTap) {
        [[iTermEventTap sharedInstance] removeObserver:self];
    }
}

- (void)unregisterCarbonHotKey {
    [[iTermCarbonHotKeyController sharedInstance] unregisterHotKey:_carbonHotKey];
    [_carbonHotKey release];
    _carbonHotKey = nil;
}

- (void)simulatePress {
    [self carbonHotkeyPressed:nil siblings:@[]];
}

- (void)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)siblings {
    [NSException raise:NSInternalInconsistencyException format:@"Not implemented. Use a subclass."];
}

- (BOOL)activationModiferPressIsDoubleTap {
    NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];
    DLog(@"You pressed the modifier key. dt=%@", @(time - _lastModifierTapTime));
    const NSTimeInterval kMaxTimeBetweenTaps = [iTermAdvancedSettingsModel hotKeyDoubleTapMaxDelay];
    BOOL result = (time - _lastModifierTapTime < kMaxTimeBetweenTaps);
    _lastModifierTapTime = time;
    return result;
}

- (void)handleActivationModifierPress {
    if ([self activationModiferPressIsDoubleTap]) {
        NSArray *siblings = [[[iTermEventTap sharedInstance] observers] mapWithBlock:^id(iTermWeakReference<id<iTermEventTapObserver>> *anObject) {
            if (![anObject.weaklyReferencedObject isKindOfClass:[self class]]) {
                return NO;
            }
            iTermBaseHotKey *other = (iTermBaseHotKey *)anObject;
            if (other.hasModifierActivation && other.modifierActivation == self.modifierActivation) {
                return anObject.weaklyReferencedObject;
            } else {
                return nil;
            }
        }];
        [self hotKeyPressedWithSiblings:siblings];
    }
}

- (BOOL)activationModifierPressedInFlags:(CGEventFlags)flags {
    if (!self.hasModifierActivation) {
        return NO;
    }
    CGEventFlags maskedFlags = (flags & kCGEventHotKeyModifierMask);

    switch (self.modifierActivation) {
        case iTermHotKeyModifierActivationShift:
            return maskedFlags == kCGEventFlagMaskAlphaShift;
            
        case iTermHotKeyModifierActivationOption:
            return maskedFlags == kCGEventFlagMaskAlternate;
            
        case iTermHotKeyModifierActivationCommand:
            return maskedFlags == kCGEventFlagMaskCommand;
            
        case iTermHotKeyModifierActivationControl:
            return maskedFlags == kCGEventFlagMaskControl;
    }
    assert(false);
}

- (void)cancelDoubleTap {
    _lastModifierTapTime = 0;
}

#pragma mark - Actions

- (void)carbonHotkeyPressed:(NSDictionary *)userInfo siblings:(NSArray<iTermHotKey *> *)siblings {
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        return;
    }
    
    NSArray *siblingBaseHotKeys = [siblings mapWithBlock:^id(iTermHotKey *anObject) {
        return anObject.target;
    }];
    [self hotKeyPressedWithSiblings:siblingBaseHotKeys];
}

#pragma mark - iTermEventTapObserver

- (void)eventTappedWithType:(CGEventType)type event:(CGEventRef)event {
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        return;
    }
    
    if (type == kCGEventFlagsChanged) {
        CGEventFlags flags = CGEventGetFlags(event);
        BOOL modifierIsPressed = [self activationModifierPressedInFlags:flags];
        if (!_modifierWasPressed && modifierIsPressed) {
            [self handleActivationModifierPress];
        } else if (_modifierWasPressed && (flags & kCGEventHotKeyModifierMask)) {
            [self cancelDoubleTap];
        }
        _modifierWasPressed = modifierIsPressed;
    } else {
        [self cancelDoubleTap];
    }
}

@end
