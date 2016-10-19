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


@interface iTermBaseHotKey()<iTermEventTapObserver>

// Override this to do a thing that needs to be done. `siblings` are other hotkeys (besides the one
// this call was made for) that have the same keypress.
- (void)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)siblings;

@end

@implementation iTermBaseHotKey {
    // The registered carbon hotkey that listens for hotkey presses.
    NSMutableArray<iTermHotKey *> *_carbonHotKeys;
    BOOL _observingEventTap;
    NSTimeInterval _lastModifierTapTime;
    BOOL _modifierWasPressed;
    BOOL _registered;
}

- (instancetype)initWithShortcuts:(NSArray<iTermShortcut *> *)shortcuts
            hasModifierActivation:(BOOL)hasModifierActivation
               modifierActivation:(iTermHotKeyModifierActivation)modifierActivation {
    self = [super init];
    if (self) {
        _shortcuts = [[shortcuts arrayByRemovingDuplicates] copy];
        _hasModifierActivation = hasModifierActivation;
        _modifierActivation = modifierActivation;
        _carbonHotKeys = [[NSMutableArray alloc] init];
    }
    return self;
}

ITERM_WEAKLY_REFERENCEABLE

- (void)iterm_dealloc {
    [_shortcuts release];
    [_carbonHotKeys release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p shortcuts=%@ modifierActivation=%@,%@>",
            NSStringFromClass([self class]), self, _shortcuts, @(self.hasModifierActivation), @(self.modifierActivation)];
}

- (NSArray<iTermHotKeyDescriptor *> *)hotKeyDescriptors {
    return [_shortcuts mapWithBlock:^id(iTermShortcut *anObject) {
        return [anObject descriptor];
    }];
}

- (iTermHotKeyDescriptor *)modifierActivationDescriptor {
    if (self.hasModifierActivation) {
        return [iTermHotKeyDescriptor descriptorWithModifierActivation:self.modifierActivation];
    } else {
        return nil;
    }
}

- (BOOL)keyDownEventIsHotKeyShortcutPress:(NSEvent *)event {
    return [_shortcuts anyWithBlock:^BOOL(iTermShortcut *anObject) {
        return [anObject eventIsShortcutPress:event];
    }];
}

- (void)register {
    DLog(@"register %@", self);
    for (iTermShortcut *shortcut in self.shortcuts) {
        [self registerShortcut:shortcut];
    }
    if (_hasModifierActivation && !_observingEventTap) {
        [[iTermEventTap sharedInstance] addObserver:self];
    }
    _registered = YES;
}

- (void)registerShortcut:(iTermShortcut *)shortcut {
    if (shortcut.isAssigned) {
        NSUInteger index = [_carbonHotKeys indexOfObjectPassingTest:^BOOL(iTermHotKey * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            // Just test if they would map to the same keycode+modifier, ignore niceties like how it displays.
            return [obj.shortcut.descriptor isEqual:shortcut.descriptor];
        }];
        if (index != NSNotFound) {
            [self unregisterCarbonHotKey:_carbonHotKeys[index]];
        }

        iTermHotKey *newHotkey =
            [[[iTermCarbonHotKeyController sharedInstance] registerShortcut:shortcut
                                                                     target:self
                                                                   selector:@selector(carbonHotkeyPressed:siblings:)
                                                                   userData:nil] retain];
        [_carbonHotKeys addObject:newHotkey];
    }

}

- (void)unregister {
    DLog(@"Unregister %@", self);
    while (_carbonHotKeys.count) {
        [self unregisterCarbonHotKey:_carbonHotKeys.firstObject];
    }
    if (_observingEventTap) {
        [[iTermEventTap sharedInstance] removeObserver:self];
    }
    _registered = NO;
}

- (void)setShortcuts:(NSArray<iTermShortcut *> *)shortcuts
    hasModifierActivation:(BOOL)hasModifierActivation
       modifierActivation:(iTermHotKeyModifierActivation)modifierActivation {
    NSSet<iTermShortcut *> *newShortcuts = [[[NSSet alloc] initWithArray:shortcuts] autorelease];
    NSSet<iTermShortcut *> *oldShortcuts = [[[NSSet alloc] initWithArray:self.shortcuts] autorelease];
    
    // NOTE:
    // It's important to detect changes to charactersIgnoringModifiers because if it's not up-to-date
    // in the carbon hotkey then keypresses while a shortcut input field is first responder will send
    // the wrong 'characters' field to it.
    if (self.hasModifierActivation == hasModifierActivation &&
        self.modifierActivation == modifierActivation &&
        [newShortcuts isEqual:oldShortcuts]) {
        // No change
        DLog(@"Attempt to change shortcuts is a no-op");
        return;
    }
    
    DLog(@"Changing shortcuts.");
    
    BOOL wasRegistered = _registered;
    if (wasRegistered) {
        [self unregister];
    }

    [_shortcuts release];
    _shortcuts = [newShortcuts.allObjects copy];
    _hasModifierActivation = hasModifierActivation;
    _modifierActivation = modifierActivation;

    if (wasRegistered) {
        [self register];
    }
}

- (void)unregisterCarbonHotKey:(iTermHotKey *)hotKey {
    [[iTermCarbonHotKeyController sharedInstance] unregisterHotKey:hotKey];
    [_carbonHotKeys removeObject:hotKey];
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
        id target = anObject.target;
        if ([target isKindOfClass:[iTermBaseHotKey class]]) {
            return target;
        } else {
            return nil;
        }
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
