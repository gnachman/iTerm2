#import "iTermCarbonHotKeyController.h"

#import "DebugLogging.h"
#import "iTermShortcutInputView.h"

#import <AppKit/AppKit.h>

NSEventModifierFlags kCarbonHotKeyModifiersMask = (NSAlphaShiftKeyMask |
                                                   NSAlternateKeyMask |
                                                   NSCommandKeyMask |
                                                   NSControlKeyMask |
                                                   NSShiftKeyMask);

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

@interface iTermHotKey : NSObject
@property(nonatomic, readonly) id target;
@property(nonatomic, readonly) SEL selector;
@property(nonatomic, readonly) NSDictionary *userData;
@property(nonatomic, readonly) EventHotKeyRef eventHotKey;
@property(nonatomic, readonly) EventHotKeyID hotKeyID;
@property(nonatomic, readonly) NSUInteger keyCode;
@property(nonatomic, readonly) UInt32 modifiers;
@property(nonatomic, readonly) NSString *characters;
@property(nonatomic, readonly) NSString *charactersIgnoringModifiers;
@end

@implementation iTermHotKey

- (instancetype)initWithEventHotKey:(EventHotKeyRef)eventHotKey
                                 id:(EventHotKeyID)hotKeyID
                            keyCode:(NSUInteger)keyCode
                          modifiers:(UInt32)modifiers
                         characters:(NSString *)characters
        charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
                           userData:(NSDictionary *)userData
                             target:(id)target
                           selector:(SEL)selector {
    self = [super init];
    if (self) {
        _eventHotKey = eventHotKey;
        _hotKeyID = hotKeyID;
        _keyCode = keyCode;
        _modifiers = modifiers;
        _characters = [characters copy];
        _charactersIgnoringModifiers = [charactersIgnoringModifiers copy];
        _target = [target retain];
        _selector = selector;
        _userData = [userData copy];
    }
    return self;
}

- (void)dealloc {
    [_target release];
    [_userData release];
    [_characters release];
    [_charactersIgnoringModifiers release];
    [super dealloc];
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

- (iTermHotKey *)registerKeyCode:(NSUInteger)keyCode
                       modifiers:(NSEventModifierFlags)modifiers
                      characters:(NSString *)characters
     charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers
                          target:(id)target
                        selector:(SEL)selector
                        userData:(NSDictionary *)userData {
    EventHotKeyRef eventHotKey = NULL;

    const UInt32 carbonModifiers = [NSEvent carbonModifiersForCocoaModifiers:modifiers];
    iTermHotKey *existingHotKey =
        [[self hotKeysWithKeyCode:keyCode modifiers:carbonModifiers] firstObject];

    EventHotKeyID hotKeyID;
    if (!existingHotKey) {
        hotKeyID = [self nextHotKeyID];
        if (RegisterEventHotKey((UInt32)keyCode,
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
                                                            keyCode:keyCode
                                                          modifiers:carbonModifiers
                                                         characters:characters
                                        charactersIgnoringModifiers:charactersIgnoringModifiers
                                                           userData:userData
                                                             target:target
                                                           selector:selector] autorelease];
    [_hotKeys addObject:hotkey];
    
    return hotkey;
}

- (void)unregisterHotKey:(iTermHotKey *)hotKey {
    [_hotKeys removeObject:hotKey];
    if ([[self hotKeysWithID:hotKey.hotKeyID] count] == 0) {
        UnregisterEventHotKey(hotKey.eventHotKey);
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

- (NSArray<iTermHotKey *> *)hotKeysWithKeyCode:(NSUInteger)keyCode modifiers:(UInt32)modifiers {
    NSMutableArray<iTermHotKey *> *result = [NSMutableArray array];
    for (iTermHotKey *hotkey in _hotKeys) {
        if (hotkey.keyCode == keyCode && hotkey.modifiers == modifiers) {
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

    NSWindow *keyWindow = [NSApp keyWindow];
    NSResponder *firstResponder = [keyWindow firstResponder];
    if ([NSApp isActive] &&
        [firstResponder isKindOfClass:[NSTextView class]] &&
        [keyWindow fieldEditor:NO forObject:nil] !=nil &&
        [[(NSTextView *)firstResponder delegate] isKindOfClass:[iTermShortcutInputView class]]) {
        // The first responder is the field editor for a shortcut input view. Let it handle it.

        iTermHotKey *hotKey = hotkeys.firstObject;
        if (!hotKey) {
            return NO;
        }
        NSEvent *fakeEvent = [NSEvent keyEventWithType:NSKeyDown
                                              location:[NSEvent mouseLocation]
                                         modifierFlags:[NSEvent cocoaModifiersForCarbonModifiers:hotKey.modifiers]
                                             timestamp:0
                                          windowNumber:[[NSApp keyWindow] windowNumber]
                                               context:nil
                                            characters:hotKey.characters
                           charactersIgnoringModifiers:hotKey.charactersIgnoringModifiers
                                             isARepeat:NO
                                               keyCode:hotKey.keyCode];
        iTermShortcutInputView *shortcutInputView = (iTermShortcutInputView *)[(NSTextView *)firstResponder delegate];
        [shortcutInputView handleShortcutEvent:fakeEvent];
        return YES;
    }

    for (iTermHotKey *hotkey in hotkeys) {
        [hotkey.target performSelector:hotkey.selector withObject:hotkey.userData];
    }

    return hotkeys.count > 0;
}


@end
