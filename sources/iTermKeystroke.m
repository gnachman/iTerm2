//
//  iTermKeystroke.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/20/20.
//

#import "iTermKeystroke.h"

#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermKeystroke

+ (instancetype)backspace {
    static iTermKeystroke *backspace;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        backspace = [[iTermKeystroke alloc] initWithVirtualKeyCode:kVK_Delete
                                                     modifierFlags:0
                                                         character:0x7f];
    });
    return backspace;
}

+ (instancetype)withEvent:(NSEvent *)event {
    NSString *unmodkeystr = [event charactersIgnoringModifiers];
    const unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    return [[self alloc] initWithVirtualKeyCode:event.keyCode
                                  modifierFlags:event.it_modifierFlags
                                      character:unmodunicode];
}

+ (instancetype)withCharacter:(unichar)character
                modifierFlags:(NSEventModifierFlags)modifierFlags {
    return [[self alloc] initWithVirtualKeyCode:0 modifierFlags:modifierFlags character:character];
}

- (instancetype)initInvalid {
    return [self initWithVirtualKeyCode:0 modifierFlags:0 character:0];
}

- (instancetype)initWithSerialized:(NSString *)serialized {
    NSString *string = [NSString castFrom:serialized];
    if (string) {
        return [self initWithString:string];
    }
    return [self initInvalid];
}

- (instancetype)initWithString:(NSString *)string {
    {
        unsigned int character = 0;
        unsigned long long flags = 0;
        unsigned int virtualKeyCode = 0;
        if (sscanf(string.UTF8String, "%x-%llx-%x", &character, &flags, &virtualKeyCode) == 3) {
            return [self initWithVirtualKeyCode:virtualKeyCode
                                  modifierFlags:flags
                                      character:character];
        }
    }
    {
        unsigned int character = 0;
        unsigned int flags = 0;
        if (sscanf(string.UTF8String, "%x-%x", &character, &flags) == 2) {
            return [self initWithVirtualKeyCode:0 modifierFlags:flags character:character];
        }
    }
    return [self initInvalid];
}

- (instancetype)initWithVirtualKeyCode:(int)virtualKeyCode
                         modifierFlags:(NSEventModifierFlags)modifierFlags
                             character:(unsigned int)character {
    self = [super init];
    if (self) {
        _virtualKeyCode = virtualKeyCode;
        _hasVirtualKeyCode = virtualKeyCode != 0;
        const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                           NSEventModifierFlagControl |
                                           NSEventModifierFlagShift |
                                           NSEventModifierFlagCommand |
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
- (NSString *)serialized {
    return [NSString stringWithFormat: @"0x%x-0x%llx-0x%x",
            self.character, (unsigned long long)self.modifierFlags, self.virtualKeyCode];
}

- (NSString *)keyInBindingDictionary:(NSDictionary<NSString *, NSDictionary *> *)dict {
    id result;
    result = dict[self.serialized];
    if (result) {
        return self.serialized;
    }
    if (dict[self.legacySerialized]) {
        return self.legacySerialized;
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

