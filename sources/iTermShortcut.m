//
//  iTermShortcut.m
//  iTerm2
//
//  Created by George Nachman on 6/27/16.
//
//

#import "iTermShortcut.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermProfilePreferences.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

// IMPORTANT: When adding to this list also update the short string class methods.
static NSString *const kKeyCode = @"keyCode";
static NSString *const kModifiers = @"modifiers";
static NSString *const kCharacters = @"characters";
static NSString *const kCharactersIgnoringModifiers = @"charactersIgnoringModifiers";

// Only append to this string! Its indexes count. Never make it longer than 10 characters. backslash -> \0, comma -> \1, space -> \2.
static NSString *sCharsToEscape = @"\\, ";

CGFloat kShortcutPreferredHeight = 22;

// The numeric keypad mask is here so we can disambiguate between keys that
// exist in both the numeric keypad and outside of it.
const NSEventModifierFlags kHotKeyModifierMask = (NSEventModifierFlagCommand |
                                                  NSEventModifierFlagOption |
                                                  NSEventModifierFlagShift |
                                                  NSEventModifierFlagControl |
                                                  NSEventModifierFlagNumericPad);

@implementation iTermShortcut {
    NSEventModifierFlags _modifiers;
}

+ (NSString *)escapedString:(NSString *)input {
    NSString *escaped = input;
    for (NSUInteger i = 0; i < sCharsToEscape.length; i++) {
        NSString *replacement = [NSString stringWithFormat:@"\\%d", (int)i];
        escaped = [escaped stringByReplacingOccurrencesOfString:[sCharsToEscape substringWithRange:NSMakeRange(i, 1)]
                                                     withString:replacement];
    }
    return escaped;
}

+ (NSString *)shortStringForDictionary:(NSDictionary *)dict {
    return [NSString stringWithFormat:@"%@,%@,%@,%@", dict[kKeyCode], dict[kModifiers], [self escapedString:dict[kCharacters]], [self escapedString:dict[kCharactersIgnoringModifiers]]];
}

+ (NSDictionary *)dictionaryForShortString:(NSString *)string {
    NSMutableString *temp = [NSMutableString string];
    NSMutableArray *parts = [NSMutableArray array];
    BOOL esc = NO;
    for (int i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (esc) {
            int j = (int)c - '0';
            if (j >= 0 && j < sCharsToEscape.length) {
                [temp appendCharacter:[sCharsToEscape characterAtIndex:j]];
            }
            esc = NO;
        } else if (c == '\\') {
            esc = YES;
        } else if (c == ',') {
            [parts addObject:temp];
            temp = [NSMutableString string];
        } else {
            [temp appendCharacter:c];
        }
    }
    [parts addObject:temp];
    if (parts.count < 4) {
        return nil;
    }
    return @{ kKeyCode: @([parts[0] iterm_unsignedIntegerValue]),
              kModifiers: @([parts[1] iterm_unsignedIntegerValue]),
              kCharacters: parts[2],
              kCharactersIgnoringModifiers: parts[3] };
}

+ (NSArray<iTermShortcut *> *)shortcutsForProfile:(Profile *)profile {
    iTermShortcut *main = [[[iTermShortcut alloc] init] autorelease];
    main.keyCode = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE inProfile:profile];
    main.modifiers = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_FLAGS inProfile:profile];
    main.characters = [iTermProfilePreferences stringForKey:KEY_HOTKEY_CHARACTERS inProfile:profile];
    main.charactersIgnoringModifiers = [iTermProfilePreferences stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS inProfile:profile];

    NSMutableArray *result =[NSMutableArray array];
    [result addObject:main];
    NSArray<NSDictionary *> *additional = (NSArray *)[profile objectForKey:KEY_HOTKEY_ALTERNATE_SHORTCUTS];
    [result addObjectsFromArray:[additional mapWithBlock:^id(NSDictionary *anObject) {
        return [self shortcutWithDictionary:anObject];
    }]];
    return [result filteredArrayUsingBlock:^BOOL(iTermShortcut *anObject) {
        return anObject.isAssigned;
    }];
}

+ (instancetype)shortcutWithDictionary:(NSDictionary *)dictionary {
    // Empty dict is the default for a profile; can't specify nil default because objc.
    if (!dictionary || !dictionary.count) {
        return nil;
    }
    iTermShortcut *shortcut = [[[iTermShortcut alloc] init] autorelease];
    shortcut.keyCode = [dictionary[kKeyCode] unsignedIntegerValue];
    shortcut.modifiers = [dictionary[kModifiers] unsignedIntegerValue];
    shortcut.characters = dictionary[kCharacters];
    shortcut.charactersIgnoringModifiers = dictionary[kCharactersIgnoringModifiers];
    return shortcut;
}

+ (instancetype)shortcutWithEvent:(NSEvent *)event {
    return [[[self alloc] initWithKeyCode:event.keyCode
                                modifiers:event.modifierFlags
                               characters:event.characters
              charactersIgnoringModifiers:event.charactersIgnoringModifiers] autorelease];
}

- (instancetype)init {
    return [self initWithKeyCode:0 modifiers:0 characters:@"" charactersIgnoringModifiers:@""];
}

- (instancetype)initWithKeyCode:(NSUInteger)code
                      modifiers:(NSEventModifierFlags)modifiers
                     characters:(NSString *)characters
    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers {
    self = [super init];
    if (self) {
        _keyCode = code;
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

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p keyCode=%@ modifiers=%@ (%@) characters=“%@” (0x%@) charactersIgnoringModifiers=“%@” (0x%@)>",
            NSStringFromClass([self class]), self, @(self.keyCode), @(self.modifiers),
            [NSString stringForModifiersWithMask:self.modifiers], self.characters, [self.characters hexEncodedString],
            self.charactersIgnoringModifiers, [self.charactersIgnoringModifiers hexEncodedString]];
}
- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[iTermShortcut class]]) {
        return [self isEqualToShortcut:object];
    } else {
        return NO;
    }
}

- (BOOL)isEqualToShortcut:(iTermShortcut *)object {
    return (object.keyCode == self.keyCode &&
            object.modifiers == self.modifiers &&
            [object.characters isEqual:self.characters] &&
            [object.charactersIgnoringModifiers isEqual:self.charactersIgnoringModifiers]);
}

- (NSUInteger)hash {
    NSArray *components = @[ @(self.keyCode),
                             @(self.modifiers),
                             self.characters ?: @"",
                             self.charactersIgnoringModifiers ?: @"" ];
    return [components hashWithDJB2];
}

#pragma mark - Accessors

- (NSDictionary *)dictionaryValue {
    return @{ kKeyCode: @(self.keyCode),
              kModifiers: @(self.modifiers),
              kCharacters: self.characters ?: @"",
              kCharactersIgnoringModifiers: self.charactersIgnoringModifiers ?: @"" };
}

- (NSString *)identifier {
    return [iTermKeyBindingMgr identifierForCharacterIgnoringModifiers:[self.charactersIgnoringModifiers firstCharacter]
                                                             modifiers:self.modifiers];
}

- (NSString *)stringValue {
    // Dead keys can have characters without charactersIgnoringModifiers. For example, option+` on
    // a German keyboard enters an apostrophe ('). The ` key is a dead key, so if you ignore modifiers
    // it's nothing. So if there are either characters or characters ignoring modifiers, it's a
    // formattable shortcut. If you press just the dead key then both characters and charactersIgnoringModifiers
    // will be empty.
    return (self.charactersIgnoringModifiers.length > 0 || self.characters.length > 0 || self.keyCode != 0) ? [iTermKeyBindingMgr formatKeyCombination:self.identifier keyCode:self.keyCode] : @"";
}

- (BOOL)isAssigned {
    return self.charactersIgnoringModifiers.length > 0 || self.characters.length > 0 || self.keyCode != 0;
}

- (iTermHotKeyDescriptor *)descriptor {
    return _charactersIgnoringModifiers.length > 0 ? [NSDictionary descriptorWithKeyCode:self.keyCode modifiers:self.modifiers] : nil;
}

- (void)setModifiers:(NSEventModifierFlags)modifiers {
    _modifiers = (modifiers & kHotKeyModifierMask);
}

- (NSEventModifierFlags)modifiers {
    // On some keyboards, arrow keys have NSEventModifierFlagNumericPad bit set; manually set it for keyboards that don't.
    if (self.keyCode >= NSUpArrowFunctionKey && self.keyCode <= NSRightArrowFunctionKey) {
        return _modifiers | NSEventModifierFlagNumericPad;
    } else {
        return _modifiers;
    }
}

#pragma mark - APIs

- (void)setFromEvent:(NSEvent *)event {
    self.keyCode = event.keyCode;
    self.characters = [event characters];
    self.charactersIgnoringModifiers = [event charactersIgnoringModifiers];
    self.modifiers = event.modifierFlags;
}

- (BOOL)eventIsShortcutPress:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return NO;
    }
    return (([event modifierFlags] & kHotKeyModifierMask) == (_modifiers & kHotKeyModifierMask) &&
            [event keyCode] == _keyCode);
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    iTermShortcut *theCopy = [[iTermShortcut alloc] init];
    theCopy.keyCode = self.keyCode;
    theCopy.modifiers = self.modifiers;
    theCopy.characters = self.characters;
    theCopy.charactersIgnoringModifiers = self.charactersIgnoringModifiers;
    return theCopy;
}

@end
