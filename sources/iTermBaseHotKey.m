#import "iTermBaseHotKey.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermEventTap.h"
#import "NSArray+iTerm.h"
#import "iTerm2SharedARC-Swift.h"

@interface iTermBaseHotKey()<iTermEventTapObserver>

// Override this to do a thing that needs to be done. `siblings` are other hotkeys (besides the one
// this call was made for) that have the same keypress.
- (NSArray<iTermBaseHotKey *> *)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)siblings;

@end

@implementation iTermBaseHotKey {
    // The registered carbon hotkey that listens for hotkey presses.
    NSMutableArray<iTermHotKey *> *_carbonHotKeys;
    iTermDoubleTapHotkeyStateMachine *_doubleTapHotkeyStateMachine;
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
        _doubleTapHotkeyStateMachine = [[iTermDoubleTapHotkeyStateMachine alloc] init];
    }
    return self;
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
    if (_hasModifierActivation && !_registered) {
        [[iTermFlagsChangedEventTap sharedInstance] addObserver:self];
        [[iTermKeyDownEventTap sharedInstance] addObserver:self];
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
        [[iTermCarbonHotKeyController sharedInstance] registerShortcut:shortcut
                                                                target:self
                                                              selector:@selector(carbonHotkeyPressed:siblings:)
                                                              userData:nil];
        [_carbonHotKeys addObject:newHotkey];
    }

}

- (void)unregister {
    DLog(@"Unregister %@", self);
    while (_carbonHotKeys.count) {
        [self unregisterCarbonHotKey:_carbonHotKeys.firstObject];
    }
    if (_registered) {
        [[iTermFlagsChangedEventTap sharedInstance] removeObserver:self];
        [[iTermKeyDownEventTap sharedInstance] removeObserver:self];
    }
    _registered = NO;
}

- (void)setShortcuts:(NSArray<iTermShortcut *> *)shortcuts
    hasModifierActivation:(BOOL)hasModifierActivation
       modifierActivation:(iTermHotKeyModifierActivation)modifierActivation {
    NSSet<iTermShortcut *> *newShortcuts = [[NSSet alloc] initWithArray:shortcuts];
    NSSet<iTermShortcut *> *oldShortcuts = [[NSSet alloc] initWithArray:self.shortcuts];

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

- (NSArray<iTermBaseHotKey *> *)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)siblings {
    [NSException raise:NSInternalInconsistencyException format:@"Not implemented. Use a subclass."];
    return nil;
}

- (void)didDoublePressActivationModifier {
    DLog(@"is double tap");
    NSArray *siblings = [[[iTermFlagsChangedEventTap sharedInstance] weakObservers] mapWithBlock:^id(iTermWeakBox<id<iTermEventTapObserver>> *box) {
        id<iTermEventTapObserver> anObject = box.object;
        if (![anObject isKindOfClass:[self class]]) {
            return nil;
        }
        iTermBaseHotKey *other = (iTermBaseHotKey *)anObject;
        if (other.hasModifierActivation && other.modifierActivation == self.modifierActivation) {
            return anObject;
        } else {
            return nil;
        }
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self hotKeyPressedWithSiblings:siblings];
    });
}

#pragma mark - Actions

- (NSArray<iTermBaseHotKey *> *)carbonHotkeyPressed:(NSDictionary *)userInfo siblings:(NSArray<iTermHotKey *> *)siblings {
    DLog(@"carbonHotkeyPressed running");
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        DLog(@"workspace session inactive");
        return nil;
    }
    if ([NSApp modalWindow]) {
        DLog(@"Ignore hotkey because there is a modal window %@", [NSApp modalWindow]);
        return nil;
    }

    // Only elements of siblings whose targets are iTermBaseHotKey
    NSArray<iTermHotKey *> *siblingHotkeys = [siblings filteredArrayUsingBlock:^BOOL(iTermHotKey *anObject) {
        id target = anObject.target;
        return ([target isKindOfClass:[iTermBaseHotKey class]]);
    }];

    // iTerMBaseHotKey's corresponding to iTermHotKey's in siblingHotkeys
    NSArray<iTermBaseHotKey *> *siblingBaseHotKeys = [siblingHotkeys mapWithBlock:^id(iTermHotKey *anObject) {
        return anObject.target;
    }];

    NSArray<iTermBaseHotKey *> *handledBaseHotkeys = [self hotKeyPressedWithSiblings:siblingBaseHotKeys];
    DLog(@"sibs are %@", siblingHotkeys);
    // Return iTermHotkey's that correspond to the handledBaseHotkeys
    return [siblingHotkeys filteredArrayUsingBlock:^BOOL(iTermHotKey *anObject) {
        return [handledBaseHotkeys containsObject:anObject.target];
    }];
}

#pragma mark - iTermEventTapObserver

- (void)eventTappedWithType:(CGEventType)type event:(CGEventRef)event {
    DLog(@"eventTappedWithType:%@ event:%@", @(type), [NSEvent eventWithCGEvent:event]);
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        DLog(@"give up because workspace session is not active");
        return;
    }

    if (type != kCGEventFlagsChanged) {
        // The purpose is to cancel double tap if you do modifier - letter - modifier.
        [_doubleTapHotkeyStateMachine reset];
        return;
    }

    [self updateDoubleTapState:event];
}

- (void)updateDoubleTapState:(CGEventRef)event {
    if (!self.hasModifierActivation) {
        DLog(@"modifier activation disabled");
        [_doubleTapHotkeyStateMachine reset];
        return;
    }
    if ([_doubleTapHotkeyStateMachine handleEvent:event activationModifier:self.modifierActivation]) {
        [self didDoublePressActivationModifier];
    }
}

@end
