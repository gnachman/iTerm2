//
//  iTermNSKeyBindingEmulator.m
//  iTerm
//
//  Created by JTheAppleSeed and George Nachman on 12/8/13.
//
//
// The purpose of this file is to parse DefaultKeyBindings.dict and to try to predict when
// keystrokes will be handled by a key binding. The first responder should call -handlesEvent: on
// each keystroke.

#import "iTermNSKeyBindingEmulator.h"
#import "DebugLogging.h"
#import <Carbon/Carbon.h>
#import <wctype.h>

@interface iTermNSKeyBindingEmulator ()

// The key binding dictionary forms a tree. This is the root of the tree.
// Entries map a "normalized key" (as produced by dictionaryKeyForCharacters:andFlags:) to either a
// dictionary subtree, or to an array with a selector and its arguments.
@property(nonatomic, retain) NSDictionary *rootDict;

// The current subtree.
@property(nonatomic, retain) NSDictionary *currentDict;

@end

// Special characters may be used in the key bindings dictionary to define buckybits required for
// the keystroke. They are always in a prefix of the key. Although they can appear in any order in
// the user's DefaultKeyBindings.dict file, once normalized they will always appear in this order
// in our keys.
static struct {
    unichar c;
    NSUInteger mask;
} gModifiers[] = {
    { '^', NSControlKeyMask },
    { '~', NSAlternateKeyMask },
    { '$', NSShiftKeyMask },
    { '#', NSNumericPadKeyMask },
    { '@', NSCommandKeyMask }
};

@implementation iTermNSKeyBindingEmulator

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                                             NSUserDomainMask,
                                                             YES);

        if ([paths count]) {
            NSString *bindPath =
                [paths[0] stringByAppendingPathComponent:@"KeyBindings/DefaultKeyBinding.dict"];
            NSDictionary *theDict = [NSDictionary dictionaryWithContentsOfFile:bindPath];
            DLog(@"Loaded key bindings dictionary:\n%@", theDict);
            _rootDict = [[self keyBindingDictionaryByNormalizingModifiersInKeys:theDict] retain];
        }
        _currentDict = [_rootDict retain];
    }
    return self;
}

- (void)dealloc {
    [_rootDict release];
    [_currentDict release];
    [super dealloc];
}

+ (instancetype)sharedInstance
{
    static dispatch_once_t once;
    static iTermNSKeyBindingEmulator *instance;
    dispatch_once(&once, ^{
        instance = [[iTermNSKeyBindingEmulator alloc] init];
    });
    return instance;
}

- (BOOL)handlesEvent:(NSEvent *)event
{
    if (!_rootDict) {
        DLog(@"Short-circuit DefaultKeyBindings handling because no bindings are defined");
        return NO;
    }
    DLog(@"Checking if default key bindings should handle %@", event);
    NSArray *possibleKeys = [self dictionaryKeysForEvent:event];
    if (possibleKeys.count == 0) {
        self.currentDict = _rootDict;
        DLog(@"Couldn't normalize event to key!");
        NSLog(@"WARNING: Unexpected charactersIgnoringModifiers=%@ in event %@",
              event.charactersIgnoringModifiers, event);
        return NO;
    }
    NSObject *obj = nil;
    NSString *selectedKey = nil;
    for (NSString *theKey in possibleKeys) {
        DLog(@"Looking up default key binding for: %@", theKey);
        obj = [_currentDict objectForKey:theKey];
        if (obj) {
            DLog(@"  Found %@", obj);
            selectedKey = theKey;
            break;
        }
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        // This is part of a multi-keystroke binding. Move down the tree.
        self.currentDict = (NSDictionary *)obj;
        DLog(@"Entered multi-keystroke binding with key: %@", selectedKey);
        return YES;
    }

    // Not (or no longer) in a multi-keystroke binding. Move to the root of the tree.
    self.currentDict = _rootDict;
    DLog(@"Default key binding is %@", obj);
    
    if (![obj isKindOfClass:[NSArray class]]) {
        return NO;
    }
    
    NSArray *theArray = (NSArray *)obj;
    return ([theArray[0] isEqualToString:@"insertText:"]);
}

#pragma mark - Private

// Return the modifer mask for a special character.
- (NSUInteger)flagsForSpecialCharacter:(unichar)c {
    for (int i = 0; i < sizeof(gModifiers) / sizeof(gModifiers[0]); i++) {
        if (gModifiers[i].c == c) {
            return gModifiers[i].mask;
        }
    }
    return 0;
}

// Returns the 0-based range of modifiers in a dictionary key such as "^A"
- (NSRange)rangeOfModifiersInDictionaryKey:(NSString *)theKey {
    if (theKey.length == 1) {
        // Special characters by themselves should be treated as keys.
        return NSMakeRange(0, 0);
    }
    int n = 0;
    for (int i = 0; i < theKey.length; i++) {
        unichar c = [theKey characterAtIndex:i];
        if ([self flagsForSpecialCharacter:c]) {
            n++;
        } else {
            return NSMakeRange(0, n);
        }
    }
    return NSMakeRange(0, n);
}

// Returns the modifier mask for a dictionary key such as "^A".
- (NSUInteger)flagsInDictionaryKey:(NSString *)theKey {
    NSRange flagsRange = [self rangeOfModifiersInDictionaryKey:theKey];
    if (flagsRange.location != 0 || flagsRange.length == 0) {
        return 0;
    }
    NSUInteger flags = 0;
    for (int i = 0; i < flagsRange.length; i++) {
        flags |= [self flagsForSpecialCharacter:[theKey characterAtIndex:i]];
    }
    return flags;
}

// Unescapes characters. \x becomes x for any character x.
- (NSString *)unescapedCharacters:(NSString *)input {
  NSMutableString *output = [NSMutableString string];
  BOOL esc = NO;
  for (int i = 0; i < input.length; i++) {
    unichar c = [input characterAtIndex:i];
    if (!esc && c == '\\') {
      esc = YES;
      continue;
    }
    [output appendFormat:@"%C", c];
    esc = NO;
  }
  return output;
}

// Returns the characters in a dictionary key such as "^A" (that is, the stuff following the
// special characters. Escaping backslashes in the character part are removed.
- (NSString *)charactersInDictionaryKey:(NSString *)theKey {
    NSRange flagsRange = [self rangeOfModifiersInDictionaryKey:theKey];
    if (flagsRange.location != 0) {
        return theKey;
    } else {
        NSString *characters = [theKey substringFromIndex:NSMaxRange(flagsRange)];
        return [self unescapedCharacters:characters];
    }
}

// Returns YES if |s| consists of a single upper case ASCII character, such as 'A' (but not '0'
// or 'a').
- (BOOL)stringIsOneUpperCaseAsciiCharacter:(NSString *)s {
    return (s.length == 1 && iswascii([s characterAtIndex:0]) && iswupper([s characterAtIndex:0]));
}

// Returns a version of |input| with normalized keys. Each key will consist of 0 or more special
// characters in the prescribed order followed by [code %d] where %d is a decimal value for the
// keystroke ignoring modifiers. There's a known bug here for nonascii keystrokes modified with
// shift--I'm not quite sure how to safely lowercase them and I lack a non-US keyboard to test with.
- (NSDictionary *)keyBindingDictionaryByNormalizingModifiersInKeys:(NSDictionary *)input {
    NSMutableDictionary *output = [NSMutableDictionary dictionary];
    for (NSString *key in input) {
        NSUInteger flags = [self flagsInDictionaryKey:key];
        NSString *characters = [self charactersInDictionaryKey:key];
        if ([self stringIsOneUpperCaseAsciiCharacter:characters]) {
            // A key of "A" is different than a key of "a". In fact, $a isn't recognized by apple's
            // parser as a capital A. This is probably not quite right (what about non-ascii
            // characters?).
            characters = [characters lowercaseString];
            flags |= NSShiftKeyMask;
        }
        NSObject *value = input[key];
        NSString *normalizedKey = [self dictionaryKeyForCharacters:characters
                                                          andFlags:flags];
        if (!normalizedKey) {
            NSLog(@"Bogus key in key bindings dictionary: %@",
                  [key dataUsingEncoding:NSUTF16BigEndianStringEncoding]);
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            NSDictionary *subDict = (NSDictionary *)value;
            output[normalizedKey] = [self keyBindingDictionaryByNormalizingModifiersInKeys:subDict];
        } else {
            output[normalizedKey] = value;
        }
    }
    return output;
}

// Parse an octal value like \010. Returns YES on success and fills in *value.
- (BOOL)parseOctal:(NSString *)s toValue:(int *)value {
    if (![s hasPrefix:@"\\0"]) {
        return NO;
    }
    if (s.length == 2) {
        return NO;
    }
    int n = 0;
    for (int i = 2; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c < '0' || c >= '8') {
            return NO;
        } else {
            n *= 8;
            n += (c - '0');
        }
    }
    if (n >= 0) {
        *value = n;
        return YES;
    } else {
        return NO;
    }
}

// Converts the "characters" part of a key to its normalized value.
- (NSString *)normalizedCharacters:(NSString *)input
{
    const int kMaxOctalValue = 31;
    input = [input lowercaseString];
    int value;
    if ([input length] == 1) {
        value = [input characterAtIndex:0];
    } else if (![self parseOctal:input toValue:&value] || value > kMaxOctalValue) {
        return nil;
    }
    return [NSString stringWithFormat:@"[code %d]", value];
}

// Returns a normalized key for characters and a modifier mask.
- (NSString *)dictionaryKeyForCharacters:(NSString *)nonNormalChars
                                andFlags:(NSUInteger)flags
{
    NSString *characters = [self normalizedCharacters:nonNormalChars];
    if (!characters) {
        return nil;
    }
    NSMutableString *theKey = [NSMutableString string];
    for (int i = 0; i < sizeof(gModifiers) / sizeof(gModifiers[0]); i++) {
        if ((gModifiers[i].mask & flags) == gModifiers[i].mask) {
            [theKey appendFormat:@"%C", gModifiers[i].c];
        }
    }
    [theKey appendString:characters];
    return theKey;
}

// Return the unshifted character in a keypress event (e.g., . for shift+.i
// (which produces ">") on a US keyboard). This may return nil.
- (NSString *)charactersIgnoringAllModifiersInEvent:(NSEvent *)event
{
    CGKeyCode keyCode = [event keyCode];
    TISInputSourceRef keyboard = TISCopyCurrentKeyboardInputSource();
    CFDataRef layoutData = TISGetInputSourceProperty(keyboard,
                                                     kTISPropertyUnicodeKeyLayoutData);
    if (!layoutData) {
        return nil;
    }
    const UCKeyboardLayout *keyboardLayout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
    UInt32 deadKeyState = 0;
    UniChar unicodeString[4];
    UniCharCount actualStringLength;

    UCKeyTranslate(keyboardLayout,
                   keyCode,
                   kUCKeyActionDisplay,
                   0,
                   LMGetKbdType(),
                   kUCKeyTranslateNoDeadKeysBit,
                   &deadKeyState,
                   sizeof(unicodeString) / sizeof(unicodeString[0]),
                   &actualStringLength,
                   unicodeString);
    CFRelease(keyboard);

    NSString *theString = (NSString *)CFStringCreateWithCharacters(kCFAllocatorDefault,
                                                                   unicodeString,
                                                                   1);
    return [theString autorelease];
}

// Returns all possible keys for an event, from most preferred to least.
// If shift is not pressed, then only one key is possible (e.g., ^A)
// If shift is pressed, then the result is [ "A", "$A" ] or [ "$<esc>" ] for chars that don't have
// an uppercase version.
- (NSArray *)dictionaryKeysForEvent:(NSEvent *)event
{
    NSString *charactersIgnoringModifiersExceptShift = [event charactersIgnoringModifiers];
    NSUInteger flags = [event modifierFlags];
    NSMutableArray *result = [NSMutableArray array];

    NSString *theKey =
        [self dictionaryKeyForCharacters:charactersIgnoringModifiersExceptShift
                                andFlags:flags];
    if (theKey) {
        [result addObject:theKey];
    }

    NSString *charactersIgnoringAllModifiers = [self charactersIgnoringAllModifiersInEvent:event];
    if (charactersIgnoringAllModifiers &&
        (flags & NSShiftKeyMask) &&
        [charactersIgnoringAllModifiers isEqualToString:charactersIgnoringAllModifiers]) {
        // The shifted version differs from the unshifted version (e.g., A vs a) so add
        // "A" since we already have "$A" ("A" is a lower priority than "$A").
        theKey =
            [self dictionaryKeyForCharacters:charactersIgnoringModifiersExceptShift
                                    andFlags:(flags & ~NSShiftKeyMask)];
        if (theKey) {
            [result addObject:theKey];
        }
    }
    return result;
}

@end
