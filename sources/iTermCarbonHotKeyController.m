#import "iTermCarbonHotKeyController.h"

#import <AppKit/AppKit.h>
#import "iTermShortcutInputView.h"

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

@end

@interface iTermHotKey : NSObject
@property(nonatomic, readonly) id target;
@property(nonatomic, readonly) SEL selector;
@property(nonatomic, readonly) NSDictionary *userData;
@property(nonatomic, readonly) EventHotKeyRef eventHotKey;
@property(nonatomic, readonly) EventHotKeyID hotKeyID;
@property(nonatomic, readonly) NSUInteger keyCode;
@property(nonatomic, readonly) UInt32 modifiers;
@end

@implementation iTermHotKey

- (instancetype)initWithEventHotKey:(EventHotKeyRef)eventHotKey
                                 id:(EventHotKeyID)hotKeyID
                            keyCode:(NSUInteger)keyCode
                          modifiers:(UInt32)modifiers
                           userData:(NSDictionary *)userData
                             target:(id)target
                           selector:(SEL)selector {
    self = [super init];
    if (self) {
        _eventHotKey = eventHotKey;
        _hotKeyID = hotKeyID;
        _keyCode = keyCode;
        _modifiers = modifiers;
        _target = [target retain];
        _selector = selector;
        _userData = [userData copy];
    }
    return self;
}

- (void)dealloc {
    [_target release];
    [_userData release];
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
        return noErr;
    } else {
        return eventNotHandledErr;
    }
}

- (BOOL)handleEvent:(EventRef)event {
    NSWindow *keyWindow = [NSApp keyWindow];
    NSResponder *firstResponder = [keyWindow firstResponder];
    if ([firstResponder isKindOfClass:[NSTextView class]] &&
        [keyWindow fieldEditor:NO forObject:nil] !=nil &&
        [[(NSTextView *)firstResponder delegate] isKindOfClass:[iTermShortcutInputView class]]) {
        // The first responder is the field editor for a shortcut input view. Let it handle it.
        return NO;
    }
    
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
    
    for (iTermHotKey *hotkey in hotkeys) {
        [hotkey.target performSelector:hotkey.selector withObject:hotkey.userData];
    }

    return hotkeys.count > 0;
}


@end
