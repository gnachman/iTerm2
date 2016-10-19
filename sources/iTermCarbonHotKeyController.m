#import "iTermCarbonHotKeyController.h"

#import "DebugLogging.h"
#import "iTermShortcutInputView.h"
#import "NSArray+iTerm.h"
#import <AppKit/AppKit.h>

@interface NSEvent(Carbon)
+ (UInt32)carbonModifiersForCocoaModifiers:(NSEventModifierFlags)flags;
@end

@implementation NSEvent(Carbon)

+ (UInt32)carbonModifiersForCocoaModifiers:(NSEventModifierFlags)cocoa {
    __block UInt32 carbon = 0;
    NSDictionary<NSNumber *, NSNumber *> *map =
        @{ @(NSAlphaShiftKeyMask): @(alphaLock),
           @(NSAlternateKeyMask): @(optionKey),
           @(NSCommandKeyMask): @(cmdKey),
           @(NSControlKeyMask): @(controlKey),
           @(NSShiftKeyMask): @(shiftKey),
         };
    [map enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
        if (cocoa & [key integerValue]) {
            carbon |= [obj intValue];
        }
    }];
    return carbon;
}

+ (NSEventModifierFlags)cocoaModifiersForCarbonModifiers:(UInt32)carbonModifiers {
    __block UInt32 x = 0;
    NSDictionary<NSNumber *, NSNumber *> *map =
    @{ @(alphaLock): @(NSAlphaShiftKeyMask),
       @(optionKey): @(NSAlternateKeyMask),
       @(cmdKey): @(NSCommandKeyMask),
       @(controlKey): @(NSControlKeyMask),
       @(shiftKey): @(NSShiftKeyMask),
       };
    [map enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
        if (carbonModifiers & [key integerValue]) {
            x |= [obj intValue];
        }
    }];
    return x;
}

@end

@implementation iTermHotKey

- (instancetype)initWithEventHotKey:(EventHotKeyRef)eventHotKey
                                 id:(EventHotKeyID)hotKeyID
                           shortcut:(iTermShortcut *)shortcut
                           userData:(NSDictionary *)userData
                             target:(id)target
                           selector:(SEL)selector {
    self = [super init];
    if (self) {
        _eventHotKey = eventHotKey;
        _hotKeyID = hotKeyID;
        _shortcut = [shortcut copy];
        _target = [target retain];
        _selector = selector;
        _userData = [userData copy];
    }
    return self;
}

- (void)dealloc {
    [_target release];
    [_userData release];
    [_shortcut release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p target=%@>", NSStringFromClass([self class]), self, _target];
}

- (BOOL)hotKeyIDEquals:(EventHotKeyID)hotKeyID {
    return hotKeyID.signature == _hotKeyID.signature && hotKeyID.id == _hotKeyID.id;
}

@end

@implementation iTermCarbonHotKeyController {
    UInt32 _nextHotKeyID;
    NSMutableArray<iTermHotKey *> *_hotKeys;
    EventHandlerRef _eventHandler;
}

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
        static EventTypeSpec events[] = {
            { kEventClassKeyboard, kEventHotKeyPressed },
        };
        if (InstallEventHandler(GetEventDispatcherTarget(),        // target
                                EventHandler,                      // handler function
                                sizeof(events) / sizeof(*events),  // number of events registering for
                                events,                            // array of events to register for
                                NULL,                              // user data to pass to EventHandler in last argument
                                &_eventHandler)) {                 // output arg for event handler reference
            return nil;
        }

        _hotKeys = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_hotKeys release];
    [super dealloc];
}

#pragma mark - APIs

- (iTermHotKey *)registerShortcut:(iTermShortcut *)shortcut
                           target:(id)target
                         selector:(SEL)selector
                         userData:(NSDictionary *)userData {
    DLog(@"Register %@ from\n%@", shortcut, [NSThread callStackSymbols]);
    
    EventHotKeyRef eventHotKey = NULL;

    const UInt32 carbonModifiers = [NSEvent carbonModifiersForCocoaModifiers:shortcut.modifiers];
    iTermHotKey *existingHotKey =
        [[self hotKeysWithKeyCode:shortcut.keyCode modifiers:shortcut.modifiers] firstObject];
    DLog(@"Registering shortcut %@. Existing hotkeys: %@", shortcut, existingHotKey);
    EventHotKeyID hotKeyID;
    if (!existingHotKey) {
        hotKeyID = [self nextHotKeyID];
        if (RegisterEventHotKey((UInt32)shortcut.keyCode,
                                carbonModifiers,
                                hotKeyID,
                                GetEventDispatcherTarget(),
                                0,
                                &eventHotKey)) {
            return nil;
        }
    } else {
        hotKeyID = existingHotKey.hotKeyID;
        eventHotKey = existingHotKey.eventHotKey;
    }

    iTermHotKey *hotkey = [[[iTermHotKey alloc] initWithEventHotKey:eventHotKey
                                                                 id:hotKeyID
                                                           shortcut:shortcut
                                                           userData:userData
                                                             target:target
                                                           selector:selector] autorelease];
    DLog(@"Register %@", hotkey);
    [_hotKeys addObject:hotkey];
    DLog(@"Hotkeys are now:\n%@", _hotKeys);
    return hotkey;
}

- (void)unregisterHotKey:(iTermHotKey *)hotKey {
    DLog(@"Unregister %@", hotKey);
    // Get the count before removing hotKey because that could free it.
    NSUInteger count = [[self hotKeysWithID:hotKey.hotKeyID] count];
    EventHotKeyRef eventHotKey = hotKey.eventHotKey;
    [_hotKeys removeObject:hotKey];
    DLog(@"Hotkeys are now:\n%@", _hotKeys);
    if (count == 1) {
        UnregisterEventHotKey(eventHotKey);
    }
}

#pragma mark - Private Methods

- (EventHotKeyID)nextHotKeyID {
    static const OSType iTermCarbonHotKeyControllerSignature = 'ITRM';
    
    EventHotKeyID keyID = {
        .signature = iTermCarbonHotKeyControllerSignature,
        .id = ++_nextHotKeyID
    };
    
    return keyID;
}

- (NSArray<iTermHotKey *> *)hotKeysWithKeyCode:(NSUInteger)keyCode
                                     modifiers:(NSEventModifierFlags)modifiers {
    NSMutableArray<iTermHotKey *> *result = [NSMutableArray array];
    for (iTermHotKey *hotkey in _hotKeys) {
        if (hotkey.shortcut.keyCode == keyCode && hotkey.shortcut.modifiers == modifiers) {
            [result addObject:hotkey];
        }
    }
    
    return result;
}

- (NSArray<iTermHotKey *> *)hotKeysWithID:(EventHotKeyID)hotKeyID {
    NSMutableArray<iTermHotKey *> *result = [NSMutableArray array];
    for (iTermHotKey *hotkey in _hotKeys) {
        if ([hotkey hotKeyIDEquals:hotKeyID]) {
            [result addObject:hotkey];
        }
    }
    return result;
}

#pragma mark - Event Handling

static OSStatus EventHandler(EventHandlerCallRef inHandler,
                             EventRef inEvent,
                             void *inUserData) {
    if ([[iTermCarbonHotKeyController sharedInstance] handleEvent:inEvent]) {
        DLog(@"Handled hotkey event");
        return noErr;
    } else {
        DLog(@"Did not handle hotkey event");
        return eventNotHandledErr;
    }
}

- (BOOL)handleEvent:(EventRef)event {
    EventHotKeyID hotKeyID;
    if (GetEventParameter(event,
                          kEventParamDirectObject,
                          typeEventHotKeyID,
                          NULL,
                          sizeof(EventHotKeyID),
                          NULL,
                          &hotKeyID)) {
        return NO;
    }

    NSArray<iTermHotKey *> *hotkeys = [self hotKeysWithID:hotKeyID];
    DLog(@"You pressed a hotkey. The registered events for this are:\n%@", hotkeys);
    
    NSWindow *keyWindow = [NSApp keyWindow];
    NSResponder *firstResponder = [keyWindow firstResponder];
    if ([NSApp isActive] &&
        [keyWindow.firstResponder isKindOfClass:[iTermShortcutInputView class]]) {
        // The first responder is a shortcut input view. Let it handle it.

        iTermHotKey *hotKey = hotkeys.firstObject;
        if (!hotKey) {
            return NO;
        }
        NSEvent *fakeEvent = [NSEvent keyEventWithType:NSKeyDown
                                              location:[NSEvent mouseLocation]
                                         modifierFlags:hotKey.shortcut.modifiers
                                             timestamp:0
                                          windowNumber:[[NSApp keyWindow] windowNumber]
                                               context:nil
                                            characters:hotKey.shortcut.characters
                           charactersIgnoringModifiers:hotKey.shortcut.charactersIgnoringModifiers
                                             isARepeat:NO
                                               keyCode:hotKey.shortcut.keyCode];
        iTermShortcutInputView *shortcutInputView = (iTermShortcutInputView *)firstResponder;
        [shortcutInputView handleShortcutEvent:fakeEvent];
        return YES;
    }

    for (iTermHotKey *hotkey in hotkeys) {
        [hotkey.target performSelector:hotkey.selector
                            withObject:hotkey.userData
                            withObject:[hotkeys arrayByRemovingObject:hotkey]];
    }

    return hotkeys.count > 0;
}


@end
