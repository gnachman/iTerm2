//
//  iTermKeystroke.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/20/20.
//

#import "iTermKeystroke.h"

#import "iTermPreferences.h"
#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

// Using this as a test for whether there is a keycode is a big red flag because 0 is the keycode for A on a US keyboard.
// It should only be used as a placeholder when the hasKeyCode flag is NO.
// When this is ported to Swift, this and hasKeyCode can go away because keycode should be an optional.
static const int iTermKeystrokeKeyCodeUnavailable = 0;

@implementation iTermKeystroke {
    // When set, self.character = self.modifiedCharacter and it should be treated as a modified
    // character. What this means in practice is that it uses a different serialization syntax.
    // This is necessary because tmux shortcuts don't expose the unmodified character. For example,
    // ! on a use keyboard should have character=1 modifiedCharacter=!, and would serialize as
    // character=1,modifiers=shift. Since that isn't an option when all we know is !, it needs
    // special treatment.
    BOOL _characterIsModified;
}

+ (instancetype)backspace {
    static iTermKeystroke *backspace;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        backspace = [[iTermKeystroke alloc] initWithVirtualKeyCode:kVK_Delete
                                                        hasKeyCode:YES
                                                     modifierFlags:0
                                                         character:0x7f
                                                 modifiedCharacter:0x7f];
    });
    return backspace;
}

+ (instancetype)withTmuxKey:(NSString *)escapedKey {
    NSMutableString *key = [escapedKey mutableCopy];
    NSInteger start = 0;
    NSRange range = [key rangeOfString:@"\\" options:0 range:NSMakeRange(start, key.length - start)];
    while (range.location != NSNotFound) {
        [key replaceCharactersInRange:range withString:@""];
        start += 1;
        range = [key rangeOfString:@"\\" options:0 range:NSMakeRange(start, key.length - start)];
    }
    NSDictionary *modifiers = @{ @('C'): @(NSEventModifierFlagControl),
                                 @('c'): @(NSEventModifierFlagControl),
                                 @('S'): @(NSEventModifierFlagShift),
                                 @('s'): @(NSEventModifierFlagShift),
                                 @('M'): @(NSEventModifierFlagOption),
                                 @('m'): @(NSEventModifierFlagOption) };

    NSDictionary *specialKeys = @{
        @"F1":         @[ @(kVK_F1),                  @(NSF1FunctionKey)],
        @"F2":         @[ @(kVK_F2),                  @(NSF2FunctionKey)],
        @"F3":         @[ @(kVK_F3),                  @(NSF3FunctionKey)],
        @"F4":         @[ @(kVK_F4),                  @(NSF4FunctionKey)],
        @"F5":         @[ @(kVK_F5),                  @(NSF5FunctionKey)],
        @"F6":         @[ @(kVK_F6),                  @(NSF6FunctionKey)],
        @"F7":         @[ @(kVK_F7),                  @(NSF7FunctionKey)],
        @"F8":         @[ @(kVK_F8),                  @(NSF8FunctionKey)],
        @"F9":         @[ @(kVK_F9),                  @(NSF9FunctionKey)],
        @"F10":        @[ @(kVK_F10),                 @(NSF10FunctionKey)],
        @"F11":        @[ @(kVK_F11),                 @(NSF11FunctionKey)],
        @"F12":        @[ @(kVK_F12),                 @(NSF12FunctionKey)],
        @"F13":        @[ @(kVK_F13),                 @(NSF13FunctionKey)],
        @"F14":        @[ @(kVK_F14),                 @(NSF14FunctionKey)],
        @"F15":        @[ @(kVK_F15),                 @(NSF15FunctionKey)],
        @"F16":        @[ @(kVK_F16),                 @(NSF16FunctionKey)],
        @"F17":        @[ @(kVK_F17),                 @(NSF17FunctionKey)],
        @"F18":        @[ @(kVK_F18),                 @(NSF18FunctionKey)],
        @"F19":        @[ @(kVK_F19),                 @(NSF19FunctionKey)],
        @"F20":        @[ @(kVK_F20),                 @(NSF20FunctionKey)],
        @"IC":         @[ @(kVK_Help),                @(NSInsertFunctionKey)],
        @"DC":         @[ @(kVK_ForwardDelete),       @(NSDeleteFunctionKey)],
        @"Home":       @[ @(kVK_Home),                @(NSHomeFunctionKey)],
        @"End":        @[ @(kVK_End),                 @(NSEndFunctionKey)],
        @"NPage":      @[ @(kVK_PageDown),            @(NSPageDownFunctionKey)],
        @"PageDown":   @[ @(kVK_PageDown),            @(NSPageDownFunctionKey)],
        @"PgDn":       @[ @(kVK_PageDown),            @(NSPageDownFunctionKey)],
        @"PPage":      @[ @(kVK_PageUp),              @(NSPageUpFunctionKey)],
        @"PageUp":     @[ @(kVK_PageUp),              @(NSPageUpFunctionKey)],
        @"PgUp":       @[ @(kVK_PageUp),              @(NSPageUpFunctionKey)],
        @"Tab":        @[ @(kVK_Tab),                 @('\t')],
        @"Space":      @[ @(kVK_Space),               @(' ')],
        @"BSpace":     @[ @(kVK_Delete),              @8],
        @"Enter":      @[ @(kVK_Return),              @('\n')],
        @"Escape":     @[ @(kVK_Escape),              @27],
        @"Up":         @[ @(kVK_UpArrow),             @(NSUpArrowFunctionKey)],
        @"Down":       @[ @(kVK_DownArrow),           @(NSDownArrowFunctionKey)],
        @"Left":       @[ @(kVK_LeftArrow),           @(NSLeftArrowFunctionKey)],
        @"Right":      @[ @(kVK_RightArrow),          @(NSRightArrowFunctionKey)],
        @"KP/":        @[ @(kVK_ANSI_KeypadDivide),   @('/')],
        @"KP*":        @[ @(kVK_ANSI_KeypadMultiply), @('*')],
        @"KP-":        @[ @(kVK_ANSI_KeypadMinus),    @('-')],
        @"KP0":        @[ @(kVK_ANSI_Keypad0),        @('0')],
        @"KP1":        @[ @(kVK_ANSI_Keypad1),        @('1')],
        @"KP2":        @[ @(kVK_ANSI_Keypad2),        @('2')],
        @"KP3":        @[ @(kVK_ANSI_Keypad3),        @('3')],
        @"KP4":        @[ @(kVK_ANSI_Keypad4),        @('4')],
        @"KP5":        @[ @(kVK_ANSI_Keypad5),        @('5')],
        @"KP6":        @[ @(kVK_ANSI_Keypad6),        @('6')],
        @"KP7":        @[ @(kVK_ANSI_Keypad7),        @('7')],
        @"KP8":        @[ @(kVK_ANSI_Keypad8),        @('8')],
        @"KP9":        @[ @(kVK_ANSI_Keypad9),        @('9')],
        @"KP+":        @[ @(kVK_ANSI_KeypadPlus),     @('+')],
        @"KPEnter":    @[ @(kVK_ANSI_KeypadEnter),    @('\n')],
        @"KP.":        @[ @(kVK_ANSI_KeypadDecimal),  @('.')]
    };

    // Get modifiers
    NSInteger i = 0;
    NSEventModifierFlags modifierFlags = (NSEventModifierFlags)iTermLeaderModifierFlag;
    while (key.length > i + 1 && [key characterAtIndex:i + 1] == '-') {
        unichar c = [key characterAtIndex:i];
        NSNumber *value = modifiers[@(c)];
        if (!value) {
            DLog(@"Unrecognized modifier %c in %@ at %@", c, key, @(i));
            return nil;
        }
        modifierFlags |= value.integerValue;
        i += 2;
    }

    int c;
    NSString *name = [key substringFromIndex:i];
    if (i + 1 == key.length) {
        // Standard ASCII key
        c = [key characterAtIndex:i];
        return [[iTermKeystroke alloc] initWithVirtualKeyCode:iTermKeystrokeKeyCodeUnavailable
                                                   hasKeyCode:NO
                                                modifierFlags:modifierFlags
                                            modifiedCharacter:c];
    }
    // special key
    NSArray *tuple = specialKeys[name];
    if (!tuple) {
        DLog(@"unrecognized key %@ in %@", name, key);
        return nil;
    }
    c = [tuple[1] intValue];
    return [[iTermKeystroke alloc] initWithVirtualKeyCode:iTermKeystrokeKeyCodeUnavailable
                                               hasKeyCode:NO
                                            modifierFlags:modifierFlags
                                                character:c
                                        modifiedCharacter:c];
}

+ (instancetype)withEvent:(NSEvent *)event {
    NSString *unmodkeystr = [event charactersIgnoringModifiers];
    const unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    return [[self alloc] initWithVirtualKeyCode:event.keyCode
                                     hasKeyCode:YES
                                  modifierFlags:event.it_modifierFlags
                                      character:unmodunicode
                              modifiedCharacter:event.characters.firstCharacter];
}

+ (instancetype)withCharacter:(unichar)character
                modifierFlags:(NSEventModifierFlags)modifierFlags {
    return [[self alloc] initWithVirtualKeyCode:iTermKeystrokeKeyCodeUnavailable
                                     hasKeyCode:NO
                                  modifierFlags:modifierFlags
                                      character:character
                              modifiedCharacter:character];
}

- (instancetype)initInvalid {
    return [self initWithVirtualKeyCode:iTermKeystrokeKeyCodeUnavailable hasKeyCode:NO modifierFlags:0 character:0 modifiedCharacter:0];
}

- (instancetype)initWithSerialized:(NSString *)serialized {
    NSString *string = [NSString castFrom:serialized];
    if (string) {
        return [self initWithString:string];
    }
    return [self initInvalid];
}

- (instancetype)initWithString:(NSString *)string {
    if ([string hasPrefix:@":"]) {
        // :0xchar:0xmods
        unsigned int character = 0;
        unsigned long long flags = 0;
        if (sscanf(string.UTF8String, ":%x:%llx", &character, &flags) == 2) {
            return [self initWithVirtualKeyCode:iTermKeystrokeKeyCodeUnavailable
                                     hasKeyCode:NO
                                  modifierFlags:flags
                              modifiedCharacter:character];
        }
        return nil;
    }
    {
        unsigned int character = 0;
        unsigned long long flags = 0;
        unsigned int virtualKeyCode = 0;
        if (sscanf(string.UTF8String, "%x-%llx-%x", &character, &flags, &virtualKeyCode) == 3) {
            return [self initWithVirtualKeyCode:virtualKeyCode
                                     hasKeyCode:YES
                                  modifierFlags:flags
                                      character:character
                              modifiedCharacter:0];
        }
    }
    {
        unsigned int character = 0;
        unsigned int flags = 0;
        if (sscanf(string.UTF8String, "%x-%x", &character, &flags) == 2) {
            return [self initWithVirtualKeyCode:0
                                     hasKeyCode:NO
                                  modifierFlags:flags
                                      character:character
                              modifiedCharacter:0];
        }
    }
    return [self initInvalid];
}

- (instancetype)initWithVirtualKeyCode:(int)virtualKeyCode
                            hasKeyCode:(BOOL)hasKeyCode
                         modifierFlags:(NSEventModifierFlags)modifierFlags
                     modifiedCharacter:(unsigned int)character {
    self = [self initWithVirtualKeyCode:virtualKeyCode
                             hasKeyCode:hasKeyCode
                          modifierFlags:modifierFlags
                              character:character
                      modifiedCharacter:character];
    if (self) {
        self->_characterIsModified = YES;
    }
    return self;
}

- (instancetype)initWithVirtualKeyCode:(int)virtualKeyCode
                            hasKeyCode:(BOOL)hasKeyCode
                         modifierFlags:(NSEventModifierFlags)modifierFlags
                             character:(unsigned int)character
                     modifiedCharacter:(UTF32Char)modifiedCharacter {
    self = [super init];
    if (self) {
        _virtualKeyCode = virtualKeyCode;
        _hasVirtualKeyCode = hasKeyCode;
        const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                           NSEventModifierFlagControl |
                                           NSEventModifierFlagShift |
                                           NSEventModifierFlagCommand |
                                           iTermLeaderModifierFlag |
                                           NSEventModifierFlagNumericPad);
        const NSEventModifierFlags sanitizedModifiers = modifierFlags & mask;

        // on some keyboards, arrow keys have NSEventModifierFlagNumericPad bit set;
        // manually set it for keyboards that don't.
        if (character >= NSUpArrowFunctionKey && character <= NSRightArrowFunctionKey) {
            _modifierFlags = sanitizedModifiers | NSEventModifierFlagNumericPad;
        } else {
            _modifierFlags = sanitizedModifiers;
        }
        _character = character;
        _modifiedCharacter = modifiedCharacter;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p char=%@ (%C) flags=0x%llx>",
            NSStringFromClass(self.class), self, @(self.character), (unichar)self.character,
            (unsigned long long)self.modifierFlags];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)legacySerialized {
    return [NSString stringWithFormat: @"0x%x-0x%x", self.character, (int)self.modifierFlags];
}

- (NSString *)modifiedSerialized {
    unsigned long long flags = (unsigned long long)self.modifierFlags;
    flags &= ~NSEventModifierFlagShift;

    if (_characterIsModified) {
        return [NSString stringWithFormat:@":0x%x:0x%llx", self.character, flags];
    }
    return [NSString stringWithFormat:@":0x%x:0x%llx", self.modifiedCharacter, flags];
}

- (NSString *)portableSerialized {
    if (_characterIsModified) {
        return [self modifiedSerialized];
    }
    if (!self.hasVirtualKeyCode) {
        return [self legacySerialized];
    }
    return [NSString stringWithFormat: @"*-0x%llx-0x%x",
            (unsigned long long)self.modifierFlags, self.virtualKeyCode];
}

- (NSString *)serialized {
    if (_characterIsModified) {
        return [self modifiedSerialized];
    }
    if (!self.hasVirtualKeyCode) {
        return [self legacySerialized];
    }
    return [NSString stringWithFormat: @"0x%x-0x%llx-0x%x",
            self.character, (unsigned long long)self.modifierFlags, self.virtualKeyCode];
}

- (NSString *)keyInBindingDictionary:(NSDictionary<NSString *, NSDictionary *> *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyLanguageAgnosticKeyBindings] && self.hasVirtualKeyCode) {
        if (dict[self.modifiedSerialized]) {
            // Note that we don't try to support language-agnostic key bindings when there's a
            // modified shortcut matching this keystroke. Otherwise, tmux shortcuts would never work
            // since they always lack a virtual keycode.
            return self.modifiedSerialized;
        }

        NSString *portableSerialized = self.portableSerialized;
        @autoreleasepool {
            for (NSString *key in dict) {
                iTermKeystroke *candidate = [[iTermKeystroke alloc] initWithString:key];
                if ([candidate.portableSerialized isEqualToString:portableSerialized]) {
                    return key;
                }
            }
        }
        if (dict[self.legacySerialized]) {
            // Fall back to a binding that doesn't include a keycode. This is necessary for
            // factory defaults to keep working, as well as bindings made prior to the addition
            // of the language-agnostic key bindings feature.
            return self.legacySerialized;
        }
        return nil;
    }
    id result;
    result = dict[self.serialized];
    if (result) {
        return self.serialized;
    }
    if (dict[self.legacySerialized]) {
        return self.legacySerialized;
    }
    if (dict[self.modifiedSerialized]) {
        return self.modifiedSerialized;
    }
    // Look for a modern key when this keystroke is legacy. Slow :(
    @autoreleasepool {
        NSString *query = self.legacySerialized;
        for (NSString *key in dict) {
            iTermKeystroke *candidate = [[iTermKeystroke alloc] initWithString:key];
            if ([candidate.legacySerialized isEqualToString:query]) {
                return key;
            }
        }
    }
    return nil;
}

- (NSDictionary *)valueInBindingDictionary:(NSDictionary<NSString *, NSDictionary *> *)dict {
    NSString *key = [self keyInBindingDictionary:dict];
    if (!key) {
        return nil;
    }
    return dict[key];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    iTermKeystroke *other = [iTermKeystroke castFrom:object];
    if (!other) {
        return NO;
    }
    return self.character == other.character && self.modifierFlags == other.modifierFlags;
}

- (NSUInteger)hash {
    return [@[ @(self.character), @(self.modifierFlags) ] hashWithDJB2];
}

- (BOOL)isValid {
    return self.character != 0;
}

- (iTermKeystroke *)keystrokeWithoutVirtualKeyCode {
    if (self.virtualKeyCode == 0) {
        return self;
    }
    return [iTermKeystroke withCharacter:_character modifierFlags:_modifierFlags];
}

- (BOOL)isNavigation {
    switch (self.virtualKeyCode) {
        case kVK_UpArrow:
        case kVK_DownArrow:
        case kVK_LeftArrow:
        case kVK_RightArrow:
        case kVK_PageUp:
        case kVK_PageDown:
        case kVK_Home:
        case kVK_End:
            return YES;

        default:
            return NO;
    }
}

@end

@implementation iTermTouchbarItem

- (instancetype)initWithIdentifier:(NSString *)identifier {
    if (![identifier hasPrefix:@"touchbar:"]) {
        return nil;
    }
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)keyInDictionary:(NSDictionary *)dict {
    if (dict[_identifier]) {
        return _identifier;
    }
    return nil;
}

@end

@implementation NSDictionary(Keystrokes)

- (NSDictionary<iTermKeystroke *, id> *)it_withDeserializedKeystrokeKeys {
    return [self mapKeysWithBlock:^iTermKeystroke *(NSString * serialized, id object) {
        return [[iTermKeystroke alloc] initWithSerialized:serialized];
    }];
}

- (NSDictionary *)it_withSerializedKeystrokeKeys {
    return [self mapKeysWithBlock:^NSString *(iTermKeystroke *key, id object) {
        return key.serialized;
    }];
}

- (NSDictionary *)it_dictionaryByMergingSerializedKeystrokeKeyedDictionary:(NSDictionary *)other {
    NSMutableDictionary *temp = [self mutableCopy];

    [other enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull serialized, id  _Nonnull obj, BOOL * _Nonnull stop) {
        iTermKeystroke *keystroke = [[iTermKeystroke alloc] initWithSerialized:serialized];
        while (1) {
            id keyToRemove = [keystroke keyInBindingDictionary:temp];
            if (!keyToRemove) {
                break;
            }
            [temp removeObjectForKey:keyToRemove];
        }
        temp[keystroke.serialized] = obj;
    }];
    return temp;
}

@end

@implementation NSString(iTermKeystroke)

- (NSComparisonResult)compareSerializedKeystroke:(NSString *)other {
    iTermKeystroke *lhsKeystroke = [[iTermKeystroke alloc] initWithSerialized:self];
    iTermKeystroke *rhsKeystroke = [[iTermKeystroke alloc] initWithSerialized:other];
    iTermTouchbarItem *lhsTouchbar = [[iTermTouchbarItem alloc] initWithIdentifier:[NSString castFrom:self]];
    iTermTouchbarItem *rhsTouchbar = [[iTermTouchbarItem alloc] initWithIdentifier:[NSString castFrom:other]];
    if (!lhsKeystroke && !rhsKeystroke) {
        return [lhsTouchbar.identifier compare:rhsTouchbar.identifier];
    }
    if (lhsKeystroke && !rhsKeystroke) {
        return NSOrderedAscending;
    }
    if (!lhsKeystroke && rhsKeystroke) {
        return NSOrderedDescending;
    }
    NSComparisonResult result;
    result = [@(lhsKeystroke.character) compare:@(rhsKeystroke.character)];
    if (result != NSOrderedSame) {
        return result;
    }
    return [@(lhsKeystroke.modifierFlags) compare:@(rhsKeystroke.modifierFlags)];
}

@end

