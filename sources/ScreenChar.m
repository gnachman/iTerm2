/*
 **  ScreenChar.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Code related to screen_char_t. Most of this has to do with
 **    storing multiple code points together in one cell by using a "color
 **    palette" approach where the code point can be used as an index into a
 **    string table, and the strings can have surrogate pairs and combining
 **    marks.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "ScreenChar.h"
#import "charmaps.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermImageInfo.h"

static NSString *const kScreenCharComplexCharMapKey = @"Complex Char Map";
static NSString *const kScreenCharInverseComplexCharMapKey = @"Inverse Complex Char Map";
static NSString *const kScreenCharImageMapKey = @"Image Map";
static NSString *const kScreenCharCCMNextKeyKey = @"Next Key";
static NSString *const kScreenCharHasWrappedKey = @"Has Wrapped";

// Maps codes to strings
static NSMutableDictionary* complexCharMap;
// Maps strings to codes.
static NSMutableDictionary* inverseComplexCharMap;
// Image info. Maps a NSNumber with the image's code to an ImageInfo object.
static NSMutableDictionary* gImages;
static NSMutableDictionary* gEncodableImageMap;
// Next available code.
static int ccmNextKey = 1;
// If ccmNextKey has wrapped then this is set to true and we have to delete old
// strings before creating a new one with a recycled code.
static BOOL hasWrapped = NO;

@interface iTermStringLine()
@property(nonatomic, retain) NSString *stringValue;
@end

@implementation iTermStringLine {
    unichar *_backingStore;
    int *_deltas;
    int _length;
}

+ (iTermStringLine *)stringLineWithString:(NSString *)string {
    screen_char_t screenChars[string.length];
    memset(screenChars, 0, string.length * sizeof(screen_char_t));
    for (int i = 0; i < string.length; i++) {
        screenChars[i].code = [string characterAtIndex:i];
        screenChars[i].complexChar = NO;
    }
    return [[[self alloc] initWithScreenChars:screenChars length:string.length] autorelease];
}

- (instancetype)initWithScreenChars:(screen_char_t *)screenChars
                             length:(NSInteger)length {
    self = [super init];
    if (self) {
        _length = length;
        _stringValue = [ScreenCharArrayToString(screenChars,
                                                0,
                                                length,
                                                &_backingStore,
                                                &_deltas) retain];
    }
    return self;
}

- (void)dealloc {
    [_stringValue release];
    if (_backingStore) {
        free(_backingStore);
    }
    if (_deltas) {
        free(_deltas);
    }
    [super dealloc];
}

- (NSRange)rangeOfScreenCharsForRangeInString:(NSRange)rangeInString {
    if (_length == 0) {
        return NSMakeRange(NSNotFound, 0);
    }

    // Convert to signed types because subtraction is used later on.
    const NSInteger location = rangeInString.location;
    const NSInteger length = rangeInString.length;
    NSInteger indexInScreenCharsOfFirstCharInRange = location + _deltas[MIN(_length - 1, location)];
    if (length == 0) {
        return NSMakeRange(indexInScreenCharsOfFirstCharInRange, 0);
    }

    const NSInteger indexInStringOfLastCharInRange = location + length - 1;
    const NSInteger indexInScreenCharsOfLastCharInRange =
        indexInStringOfLastCharInRange + _deltas[MIN(_length - 1, indexInStringOfLastCharInRange)];
    const NSInteger numberOfScreenChars =
        indexInScreenCharsOfLastCharInRange - indexInScreenCharsOfFirstCharInRange + 1;
    return NSMakeRange(indexInScreenCharsOfFirstCharInRange, numberOfScreenChars);
}

@end

@implementation ScreenCharArray
@synthesize line = _line;
@synthesize length = _length;
@synthesize eol = _eol;
@end

static void CreateComplexCharMapIfNeeded() {
    if (!complexCharMap) {
        complexCharMap = [[NSMutableDictionary alloc] initWithCapacity:1000];
        // Add box-drawing chars, which are reserved. They are drawn using
        // bezier paths but it's important that the keys refer to an existing
        // string for general correctness.
        for (int i = 0; i < 256; i++) {
            if (lineDrawingCharFlags[i]) {
                complexCharMap[@(charmap[i])] = [NSString stringWithFormat:@"%C", charmap[i]];
            }
        }
        inverseComplexCharMap = [[NSMutableDictionary alloc] initWithCapacity:1000];
    }
}

NSString* ComplexCharToStr(int key)
{
    if (key == UNICODE_REPLACEMENT_CHAR) {
        return ReplacementString();
    }

    CreateComplexCharMapIfNeeded();
    return [complexCharMap objectForKey:[NSNumber numberWithInt:key]];
}

NSString* ScreenCharToStr(screen_char_t* sct)
{
    return CharToStr(sct->code, sct->complexChar);
}

NSString* CharToStr(unichar code, BOOL isComplex)
{
    if (code == UNICODE_REPLACEMENT_CHAR) {
        return ReplacementString();
    }

    if (isComplex) {
        return ComplexCharToStr(code);
    } else {
        return [NSString stringWithCharacters:&code length:1];
    }
}

int ExpandScreenChar(screen_char_t* sct, unichar* dest) {
    NSString* value = nil;
    if (sct->code == UNICODE_REPLACEMENT_CHAR) {
        value = ReplacementString();
    } else if (sct->complexChar) {
        value = ComplexCharToStr(sct->code);
    } else {
        *dest = sct->code;
        return 1;
    }
    if (!value) {
        // This can happen if state restoration goes awry.
        return 0;
    }
    [value getCharacters:dest];
    return (int)[value length];
}

UTF32Char CharToLongChar(unichar code, BOOL isComplex)
{
    NSString* aString = CharToStr(code, isComplex);
    unichar firstChar = [aString characterAtIndex:0];
    if (IsHighSurrogate(firstChar) && [aString length] >= 2) {
        unichar secondChar = [aString characterAtIndex:0];
        return DecodeSurrogatePair(firstChar, secondChar);
    } else {
        return firstChar;
    }
}

static BOOL ComplexCharKeyIsReserved(int k) {
    switch (k) {
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_LEFT:
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_LEFT:
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_RIGHT:
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_RIGHT:
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_HORIZONTAL:
        case ITERM_BOX_DRAWINGS_LIGHT_HORIZONTAL:
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_RIGHT:
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL_AND_LEFT:
        case ITERM_BOX_DRAWINGS_LIGHT_UP_AND_HORIZONTAL:
        case ITERM_BOX_DRAWINGS_LIGHT_DOWN_AND_HORIZONTAL:
        case ITERM_BOX_DRAWINGS_LIGHT_VERTICAL:
            return YES;

        default:
            return NO;
    }
}

static void AllocateImageMapsIfNeeded(void) {
    if (!gImages) {
        gImages = [[NSMutableDictionary alloc] init];
        gEncodableImageMap = [[NSMutableDictionary alloc] init];
    }
}

screen_char_t ImageCharForNewImage(NSString *name, int width, int height, BOOL preserveAspectRatio)
{
    AllocateImageMapsIfNeeded();
    int newKey;
    do {
        newKey = ccmNextKey++;
    } while (ComplexCharKeyIsReserved(newKey));

    screen_char_t c = { 0 };
    c.image = 1;
    c.code = newKey;

    iTermImageInfo *imageInfo = [[[iTermImageInfo alloc] initWithCode:c.code] autorelease];
    imageInfo.filename = name;
    imageInfo.preserveAspectRatio = preserveAspectRatio;
    imageInfo.size = NSMakeSize(width, height);
    gImages[@(c.code)] = imageInfo;

    return c;
}

void SetPositionInImageChar(screen_char_t *charPtr, int x, int y)
{
    charPtr->foregroundColor = x;
    charPtr->backgroundColor = y;
}

void SetDecodedImage(unichar code, NSImage *image, NSData *data) {
    iTermImageInfo *imageInfo = gImages[@(code)];
    [imageInfo setImageFromImage:image data:data];
    gEncodableImageMap[@(code)] = [imageInfo dictionary];
}

void ReleaseImage(unichar code) {
    [gImages removeObjectForKey:@(code)];
    [gEncodableImageMap removeObjectForKey:@(code)];
}

iTermImageInfo *GetImageInfo(unichar code) {
    return gImages[@(code)];
}

VT100GridCoord GetPositionOfImageInChar(screen_char_t c) {
    return VT100GridCoordMake(c.foregroundColor,
                              c.backgroundColor);
}

int GetOrSetComplexChar(NSString* str)
{
    CreateComplexCharMapIfNeeded();
    NSNumber* number = [inverseComplexCharMap objectForKey:str];
    if (number) {
        return [number intValue];
    }

    int newKey;
    do {
        newKey = ccmNextKey++;
    } while (ComplexCharKeyIsReserved(newKey));

    number = @(newKey);
    if (hasWrapped) {
        NSString* oldStr = complexCharMap[number];
        if (oldStr) {
            [inverseComplexCharMap removeObjectForKey:oldStr];
        }
    }
    complexCharMap[number] = str;
    inverseComplexCharMap[str] = number;
    if ([iTermAdvancedSettingsModel restoreWindowContents]) {
        [NSApp invalidateRestorableState];
    }
    if (ccmNextKey == 0xf000) {
        ccmNextKey = 1;
        hasWrapped = YES;
    }
    return newKey;
}

int AppendToComplexChar(int key, unichar codePoint)
{
    if (key == UNICODE_REPLACEMENT_CHAR) {
        return UNICODE_REPLACEMENT_CHAR;
    }

    NSString* str = [complexCharMap objectForKey:[NSNumber numberWithInt:key]];
    if ([str length] == kMaxParts) {
        NSLog(@"Warning: char <<%@>> with key %d reached max length %d", str,
              key, kMaxParts);
        return key;
    }
    assert(str);
    NSMutableString* temp = [NSMutableString stringWithString:str];
    [temp appendString:[NSString stringWithCharacters:&codePoint length:1]];

    return GetOrSetComplexChar(temp);
}

void BeginComplexChar(screen_char_t *screenChar, unichar combiningChar, BOOL useHFSPlusMapping) {
    unichar initialCodePoint = screenChar->code;
    if (initialCodePoint == UNICODE_REPLACEMENT_CHAR) {
        return;
    }

    unichar temp[2];
    temp[0] = initialCodePoint;
    temp[1] = combiningChar;
    
    // See if it makes a single code in NFC.
    NSString *theString = [NSString stringWithCharacters:temp length:2];
    NSString *nfc = useHFSPlusMapping ? [theString precomposedStringWithHFSPlusMapping] :
                                        [theString precomposedStringWithCanonicalMapping];
    if (nfc.length == 1) {
        screenChar->code = [nfc characterAtIndex:0];
    } else {
        screenChar->code = GetOrSetComplexChar([NSString stringWithCharacters:temp length:2]);
        screenChar->complexChar = YES;
    }
}

BOOL StringContainsCombiningMark(NSString *s)
{
    if (s.length < 2) return NO;
    UTF32Char value = 0;
    unichar high = 0;
    for (int i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (high) {
            if (IsLowSurrogate(c)) {
                value = DecodeSurrogatePair(high, c);
                high = 0;
            } else {
                high = 0;
                continue;
            }
        } else if (IsHighSurrogate(c)) {
            high = c;
            continue;
        } else {
            value = c;
        }
        if (IsCombiningMark(value)) {
            return YES;
        }
    }
    return NO;
}


BOOL IsCombiningMark(UTF32Char c)
{
    static NSCharacterSet* combiningMarks;
    if (!combiningMarks) {
        struct {
            int minVal;
            int maxVal;
        } ranges[] = {
            // These are all the combining marks in Unicode 6.0 from:
            // http://www.fileformat.info/info/unicode/category/Mc/list.htm
            // http://www.fileformat.info/info/unicode/category/Mn/list.htm
            // http://www.fileformat.info/info/unicode/category/Me/list.htm
            //
            // Per http://www.unicode.org/versions/Unicode6.0.0/ch03.pdf#G30602
            // D52, Spacing Combining Marks, Nonspacing Marks, and
            // Enclosing Marks make up the set of combining marks.
            { 0x300, 0x36f }, { 0x483, 0x489 }, { 0x591, 0x5bd }, { 0x5bf, 0x5bf },
            { 0x5c1, 0x5c2 }, { 0x5c4, 0x5c5 }, { 0x5c7, 0x5c7 }, { 0x610, 0x61a },
            { 0x64b, 0x65f }, { 0x670, 0x670 }, { 0x6d6, 0x6dc }, { 0x6df, 0x6e4 },
            { 0x6e7, 0x6e8 }, { 0x6ea, 0x6ed }, { 0x711, 0x711 }, { 0x730, 0x74a },
            { 0x7a6, 0x7b0 }, { 0x7eb, 0x7f3 }, { 0x816, 0x819 }, { 0x81b, 0x823 },
            { 0x825, 0x827 }, { 0x829, 0x82d }, { 0x859, 0x85b }, { 0x900, 0x903 },
            { 0x93a, 0x93c }, { 0x93e, 0x94f }, { 0x951, 0x957 }, { 0x962, 0x963 },
            { 0x981, 0x983 }, { 0x9bc, 0x9bc }, { 0x9be, 0x9c4 }, { 0x9c7, 0x9c8 },
            { 0x9cb, 0x9cd }, { 0x9d7, 0x9d7 }, { 0x9e2, 0x9e3 }, { 0xa01, 0xa03 },
            { 0xa3c, 0xa3c }, { 0xa3e, 0xa42 }, { 0xa47, 0xa48 }, { 0xa4b, 0xa4d },
            { 0xa51, 0xa51 }, { 0xa70, 0xa71 }, { 0xa75, 0xa75 }, { 0xa81, 0xa83 },
            { 0xabc, 0xabc }, { 0xabe, 0xac5 }, { 0xac7, 0xac9 }, { 0xacb, 0xacd },
            { 0xae2, 0xae3 }, { 0xb01, 0xb03 }, { 0xb3c, 0xb3c }, { 0xb3e, 0xb44 },
            { 0xb47, 0xb48 }, { 0xb4b, 0xb4d }, { 0xb56, 0xb57 }, { 0xb62, 0xb63 },
            { 0xb82, 0xb82 }, { 0xbbe, 0xbc2 }, { 0xbc6, 0xbc8 }, { 0xbca, 0xbcd },
            { 0xbd7, 0xbd7 }, { 0xc01, 0xc03 }, { 0xc3e, 0xc44 }, { 0xc46, 0xc48 },
            { 0xc4a, 0xc4d }, { 0xc55, 0xc56 }, { 0xc62, 0xc63 }, { 0xc82, 0xc83 },
            { 0xcbc, 0xcbc }, { 0xcbe, 0xcc4 }, { 0xcc6, 0xcc8 }, { 0xcca, 0xccd },
            { 0xcd5, 0xcd6 }, { 0xce2, 0xce3 }, { 0xd02, 0xd03 }, { 0xd3e, 0xd44 },
            { 0xd46, 0xd48 }, { 0xd4a, 0xd4d }, { 0xd57, 0xd57 }, { 0xd62, 0xd63 },
            { 0xd82, 0xd83 }, { 0xdca, 0xdca }, { 0xdcf, 0xdd4 }, { 0xdd6, 0xdd6 },
            { 0xdd8, 0xddf }, { 0xdf2, 0xdf3 }, { 0xe31, 0xe31 }, { 0xe34, 0xe3a },
            { 0xe47, 0xe4e }, { 0xeb1, 0xeb1 }, { 0xeb4, 0xeb9 }, { 0xebb, 0xebc },
            { 0xec8, 0xecd }, { 0xf18, 0xf19 }, { 0xf35, 0xf35 }, { 0xf37, 0xf37 },
            { 0xf39, 0xf39 }, { 0xf3e, 0xf3f }, { 0xf71, 0xf84 }, { 0xf86, 0xf87 },
            { 0xf8d, 0xf97 }, { 0xf99, 0xfbc }, { 0xfc6, 0xfc6 }, { 0x102b, 0x103e },
            { 0x1056, 0x1059 }, { 0x105e, 0x1060 }, { 0x1062, 0x1064 }, { 0x1067, 0x106d },
            { 0x1071, 0x1074 }, { 0x1082, 0x108d }, { 0x108f, 0x108f }, { 0x109a, 0x109d },
            { 0x135d, 0x135f }, { 0x1712, 0x1714 }, { 0x1732, 0x1734 }, { 0x1752, 0x1753 },
            { 0x1772, 0x1773 }, { 0x17b6, 0x17d3 }, { 0x17dd, 0x17dd }, { 0x180b, 0x180d },
            { 0x18a9, 0x18a9 }, { 0x1920, 0x192b }, { 0x1930, 0x193b }, { 0x19b0, 0x19c0 },
            { 0x19c8, 0x19c9 }, { 0x1a17, 0x1a1b }, { 0x1a55, 0x1a5e }, { 0x1a60, 0x1a7c },
            { 0x1a7f, 0x1a7f }, { 0x1b00, 0x1b04 }, { 0x1b34, 0x1b44 }, { 0x1b6b, 0x1b73 },
            { 0x1b80, 0x1b82 }, { 0x1ba1, 0x1baa }, { 0x1be6, 0x1bf3 }, { 0x1c24, 0x1c37 },
            { 0x1cd0, 0x1cd2 }, { 0x1cd4, 0x1ce8 }, { 0x1ced, 0x1ced }, { 0x1cf2, 0x1cf2 },
            { 0x1dc0, 0x1de6 }, { 0x1dfc, 0x1dff }, { 0x20d0, 0x20f0 }, { 0x2cef, 0x2cf1 },
            { 0x2d7f, 0x2d7f }, { 0x2de0, 0x2dff }, { 0x302a, 0x302f }, { 0x3099, 0x309a },
            { 0xa66f, 0xa672 }, { 0xa67c, 0xa67d }, { 0xa6f0, 0xa6f1 }, { 0xa802, 0xa802 },
            { 0xa806, 0xa806 }, { 0xa80b, 0xa80b }, { 0xa823, 0xa827 }, { 0xa880, 0xa881 },
            { 0xa8b4, 0xa8c4 }, { 0xa8e0, 0xa8f1 }, { 0xa926, 0xa92d }, { 0xa947, 0xa953 },
            { 0xa980, 0xa983 }, { 0xa9b3, 0xa9c0 }, { 0xaa29, 0xaa36 }, { 0xaa43, 0xaa43 },
            { 0xaa4c, 0xaa4d }, { 0xaa7b, 0xaa7b }, { 0xaab0, 0xaab0 }, { 0xaab2, 0xaab4 },
            { 0xaab7, 0xaab8 }, { 0xaabe, 0xaabf }, { 0xaac1, 0xaac1 }, { 0xabe3, 0xabea },
            { 0xabec, 0xabed }, { 0xfb1e, 0xfb1e }, { 0xfe00, 0xfe0f }, { 0xfe20, 0xfe26 },
            { 0x101fd, 0x101fd }, { 0x10a01, 0x10a03 }, { 0x10a05, 0x10a06 },
            { 0x10a0c, 0x10a0f }, { 0x10a38, 0x10a3a }, { 0x10a3f, 0x10a3f },
            { 0x11000, 0x11002 }, { 0x11038, 0x11046 }, { 0x11080, 0x11082 },
            { 0x110b0, 0x110ba }, { 0x1d165, 0x1d169 }, { 0x1d16d, 0x1d172 },
            { 0x1d17b, 0x1d182 }, { 0x1d185, 0x1d18b }, { 0x1d1aa, 0x1d1ad },
            { 0x1d242, 0x1d244 },
            { 0xe0100, 0xe01ef },
            { 0, 0 }
        };

        NSMutableCharacterSet* temp = [[NSMutableCharacterSet alloc] init];
        for (int i = 0; ranges[i].minVal; ++i) {
            for (int j = ranges[i].minVal; j <= ranges[i].maxVal; ++j) {
                [temp addCharactersInRange:NSMakeRange(ranges[i].minVal,
                                                       ranges[i].maxVal - ranges[i].minVal + 1)];
            }
        }
        combiningMarks = temp;
    }
    return [combiningMarks longCharacterIsMember:c];
}

UTF32Char DecodeSurrogatePair(unichar high, unichar low)
{
    return 0x10000 + (high - 0xd800) * 0x400 + (low - 0xdc00);
}

BOOL IsLowSurrogate(unichar c)
{
    // http://en.wikipedia.org/wiki/Mapping_of_Unicode_characters#Surrogates
    return c >= 0xdc00 && c <= 0xdfff;
}

BOOL IsHighSurrogate(unichar c)
{
    // http://en.wikipedia.org/wiki/Mapping_of_Unicode_characters#Surrogates
    return c >= 0xd800 && c <= 0xdbff;
}

NSString* ScreenCharArrayToString(screen_char_t* screenChars,
                                  int start,
                                  int end,
                                  unichar** backingStorePtr,
                                  int** deltasPtr) {
    const int lineLength = end - start;
    unichar* charHaystack = malloc(sizeof(unichar) * lineLength * kMaxParts + 1);
    *backingStorePtr = charHaystack;
    int* deltas = malloc(sizeof(int) * (lineLength * kMaxParts + 1));
    *deltasPtr = deltas;
    // The 'deltas' array gives the difference in position between the screenChars
    // and the charHaystack. The formula to convert an index in the charHaystack
    // 'i' into an index in the screenChars 'r' is:
    //     r = i + deltas[i]
    //
    // Array of screen_char_t with some double-width characters, where DWC_RIGHT is
    // shown as '-', and d & f have combining marks/surrogate pairs (not shown here):
    // 0123456789
    // ab-c-de-fg
    //
    // charHaystack, with combining marks/low surrogates shown as '*':
    // 0123456789A
    // abcd**ef**g
    //
    // Mapping:
    // charHaystack index i -> screenChars index  deltas[i]
    // 0 -> 0   (a@0->a@0)                        0
    // 1 -> 1   (b@1->b-@1)                       0
    // 2 -> 3   (c@2->c-@3)                       1
    // 3 -> 5   (d@3->d@5)                        2
    // 4 -> 5   (*@4->d@5)                        1
    // 5 -> 5   (*@5->d@5)                        0
    // 6 -> 6   (e@6->e-@6)                       0
    // 7 -> 8   (f@7->f@8)                        1
    // 8 -> 8   (*@8->f@8)                        0
    // 9 -> 8   (*@9->f@8)                       -1
    // A -> 9   (g@A->g@9)                       -1
    //
    // Note that delta is just the difference of the indices.
    //
    // screen_char_t[i + deltas[i]] begins its run at charHaystack[i]
    // CharHaystackIndexToScreenCharTIndex(i) : i + deltas[i]
    int delta = 0;
    int o = 0;
    for (int i = start; i < end; ++i) {
        unichar c = screenChars[i].code;
        if (c == DWC_RIGHT) {
            ++delta;
        } else {
            const int len = ExpandScreenChar(&screenChars[i], charHaystack + o);
            ++delta;
            for (int j = o; j < o + len; ++j) {
                deltas[j] = --delta;
            }
            o += len;
        }
    }
    deltas[o] = delta;

    return CharArrayToString(charHaystack, o);
}

NSString* CharArrayToString(unichar* charHaystack, int o)
{
    // I have no idea why NSUnicodeStringEncoding doesn't work, but it has
    // the wrong endianness on x86. Perhaps it's a relic of PPC days? Anyway,
    // LittleEndian seems to work on my x86, and BigEndian works under Rosetta
    // with a ppc-only binary. Oddly, testing for defined(LITTLE_ENDIAN) does
    // not produce the correct results under ppc+Rosetta.
    int encoding;
#if defined(__ppc__) || defined(__ppc64__)
    encoding = NSUTF16BigEndianStringEncoding;
#else
    encoding = NSUTF16LittleEndianStringEncoding;
#endif
    return [[[NSString alloc] initWithBytesNoCopy:charHaystack
                                           length:o * sizeof(unichar)
                                         encoding:encoding
                                     freeWhenDone:NO] autorelease];
}

void DumpScreenCharArray(screen_char_t* screenChars, int lineLength) {
    NSLog(@"%@", ScreenCharArrayToStringDebug(screenChars, lineLength));
}

NSString* ScreenCharArrayToStringDebug(screen_char_t* screenChars,
                                       int lineLength) {
    while (lineLength > 0 && screenChars[lineLength - 1].code == 0) {
        --lineLength;
    }
    NSMutableString* result = [NSMutableString stringWithCapacity:lineLength];
    for (int i = 0; i < lineLength; ++i) {
        unichar c = screenChars[i].code;
        if (c != 0 && c != DWC_RIGHT) {
            [result appendString:ScreenCharToStr(&screenChars[i])];
        }
    }
    return result;
}

int EffectiveLineLength(screen_char_t* theLine, int totalLength) {
    for (int i = totalLength - 1; i >= 0; i--) {
        if (theLine[i].complexChar || theLine[i].code) {
            return i + 1;
        }
    }
    return 0;
}

// Convert a string into an array of screen characters, dealing with surrogate
// pairs, combining marks, nonspacing marks, and double-width characters.
void StringToScreenChars(NSString *s,
                         screen_char_t *buf,
                         screen_char_t fg,
                         screen_char_t bg,
                         int *len,
                         BOOL ambiguousIsDoubleWidth,
                         int* cursorIndex,
                         BOOL *foundDwc,
                         BOOL useHFSPlusMapping) {
    unichar *sc;
    int l = [s length];
    int i;
    int j;

    const int kBufferElements = 1024;
    unichar staticBuffer[kBufferElements];
    unichar* dynamicBuffer = 0;
    if ([s length] > kBufferElements) {
        sc = dynamicBuffer = (unichar *) calloc(l, sizeof(unichar));
    } else {
        sc = staticBuffer;
    }

    [s getCharacters:sc];
    BOOL foundCursor = NO;
    for (i = j = 0; i < l; i++, j++) {
        if (cursorIndex && !foundCursor && *cursorIndex == i) {
            foundCursor = YES;
            *cursorIndex = j;
        }

        // Naïvely copy the input char into the output buf.
        buf[j].code = sc[i];
        buf[j].complexChar = NO;

        buf[j].foregroundColor = fg.foregroundColor;
        buf[j].fgGreen = fg.fgGreen;
        buf[j].fgBlue = fg.fgBlue;

        buf[j].backgroundColor = bg.backgroundColor;
        buf[j].bgGreen = bg.bgGreen;
        buf[j].bgBlue = bg.bgBlue;

        buf[j].foregroundColorMode = fg.foregroundColorMode;
        buf[j].backgroundColorMode = bg.backgroundColorMode;

        buf[j].bold = fg.bold;
        buf[j].faint = fg.faint;
        buf[j].italic = fg.italic;
        buf[j].blink = fg.blink;
        buf[j].underline = fg.underline;
        buf[j].image = NO;

        buf[j].unused = 0;

        // Now fix up buf, dealing with private-use characters, zero-width spaces,
        // combining marks, and surrogate pairs.
        if (sc[i] >= ITERM2_PRIVATE_BEGIN && sc[i] <= ITERM2_PRIVATE_END) {
            // Translate iTerm2's private-use characters into a "?".
            buf[j].code = '?';
        } else if (sc[i] > 0xa0 &&
                   !IsCombiningMark(sc[i]) &&
                   !IsLowSurrogate(sc[i]) &&
                   !IsHighSurrogate(sc[i]) &&
                   [NSString isDoubleWidthCharacter:sc[i]
                             ambiguousIsDoubleWidth:ambiguousIsDoubleWidth]) {
            // This code path is for double-width characters in BMP only. Append a DWC_RIGHT.
            j++;
            buf[j].code = DWC_RIGHT;
            if (foundDwc) {
                *foundDwc = YES;
            }
            buf[j].complexChar = NO;

            buf[j].foregroundColor = fg.foregroundColor;
            buf[j].fgGreen = fg.fgGreen;
            buf[j].fgBlue = fg.fgBlue;

            buf[j].backgroundColor = bg.backgroundColor;
            buf[j].bgGreen = bg.fgGreen;
            buf[j].bgBlue = bg.fgBlue;

            buf[j].foregroundColorMode = fg.foregroundColorMode;
            buf[j].backgroundColorMode = bg.backgroundColorMode;

            buf[j].bold = fg.bold;
            buf[j].faint = fg.faint;
            buf[j].italic = fg.italic;
            buf[j].blink = fg.blink;
            buf[j].underline = fg.underline;

            buf[j].unused = 0;
        } else if (sc[i] == 0xfeff ||  // zero width no-break space
                   sc[i] == 0x200b ||  // zero width space
                   sc[i] == 0x200c ||  // zero width non-joiner
                   sc[i] == 0x200d) {  // zero width joiner
            // Just act like we never saw the character. This isn't quite right because a subsequent
            // combining mark should not combine with a space.
            j--;
        } else if (IsCombiningMark(sc[i]) || IsLowSurrogate(sc[i])) {
            // In the case of a surrogate pair, the high surrogate will be placed in buf in the
            // preceding iteration. When we see a low surrogate and the j-1'th char in buf is a
            // high surrogate, then a complex char gets created at j-1. In that way, a low surrogate
            // acts like a combining mark, which is why the two cases are handled together here.
            if (j > 0) {
                // Undo the initialization of the j'th character because we won't use it
                j--;

                BOOL movedBackOverDwcRight = NO;
                if (buf[j].code == DWC_RIGHT && j > 0 && IsCombiningMark(sc[i])) {
                    // This happens easily with ambiguous-width characters, where something like
                    // á is treated as double-width and a subsequent combining mark needs to modify
                    // at the real code, not the DWC_RIGHT. Decrement j temporarily.
                    j--;
                    movedBackOverDwcRight = YES;
                }
                if (buf[j].complexChar) {
                    // Adding a combining mark to a char that already has one or was
                    // built by surrogates.
                    buf[j].code = AppendToComplexChar(buf[j].code, sc[i]);
                } else {
                    // Turn buf[j] into a complex char by adding sc[i] to it.
                    BeginComplexChar(buf + j, sc[i], useHFSPlusMapping);
                }
                if (movedBackOverDwcRight) {
                    // Undo the temporary decrement of j
                    j++;
                }
                if (IsLowSurrogate(sc[i]) && !movedBackOverDwcRight) {
                    // We have the second part of a surrogate pair which may cause the character
                    // to become double-width. If so, tack on a DWC_RIGHT.
                    NSString* str = ComplexCharToStr(buf[j].code);
                    if ([NSString isDoubleWidthCharacter:DecodeSurrogatePair([str characterAtIndex:0], [str characterAtIndex:1])
                                  ambiguousIsDoubleWidth:ambiguousIsDoubleWidth]) {
                        j++;
                        buf[j].code = DWC_RIGHT;
                        if (foundDwc) {
                            *foundDwc = YES;
                        }
                        buf[j].complexChar = NO;

                        buf[j].foregroundColor = fg.foregroundColor;
                        buf[j].fgGreen = fg.fgGreen;
                        buf[j].fgBlue = fg.fgBlue;

                        buf[j].backgroundColor = bg.backgroundColor;
                        buf[j].bgGreen = bg.fgGreen;
                        buf[j].bgBlue = bg.fgBlue;

                        buf[j].foregroundColorMode = fg.foregroundColorMode;
                        buf[j].backgroundColorMode = bg.backgroundColorMode;

                        buf[j].bold = fg.bold;
                        buf[j].faint = fg.faint;
                        buf[j].italic = fg.italic;
                        buf[j].blink = fg.blink;
                        buf[j].underline = fg.underline;

                        buf[j].unused = 0;
                    }
                }
            }
        }
    }
    *len = j;
    if (cursorIndex && !foundCursor && *cursorIndex >= i) {
        // We were asked for the position of the cursor to the right
        // of the last character.
        *cursorIndex = j;
    }
    if (dynamicBuffer) {
        free(dynamicBuffer);
    }
}

void ConvertCharsToGraphicsCharset(screen_char_t *s, int len)
{
    int i;

    for (i = 0; i < len; i++) {
        assert(!s[i].complexChar);
        s[i].complexChar = lineDrawingCharFlags[(int)(s[i].code)];
        s[i].code = charmap[(int)(s[i].code)];
    }
}

NSDictionary *ScreenCharEncodedRestorableState(void) {
    return @{ kScreenCharComplexCharMapKey: complexCharMap ?: @{},
              kScreenCharInverseComplexCharMapKey: inverseComplexCharMap ?: @{},
              kScreenCharImageMapKey: gEncodableImageMap ?: @{},
              kScreenCharCCMNextKeyKey: @(ccmNextKey),
              kScreenCharHasWrappedKey: @(hasWrapped) };
}

void ScreenCharDecodeRestorableState(NSDictionary *state) {
    NSDictionary *stateComplexCharMap = state[kScreenCharComplexCharMapKey];
    if (!complexCharMap && stateComplexCharMap.count) {
        complexCharMap = [[NSMutableDictionary alloc] init];
    }
    for (id key in stateComplexCharMap) {
        if (!complexCharMap[key]) {
            complexCharMap[key] = stateComplexCharMap[key];
        }
    }

    NSDictionary *stateInverseMap = state[kScreenCharInverseComplexCharMapKey];
    if (!inverseComplexCharMap && stateInverseMap.count) {
        inverseComplexCharMap = [[NSMutableDictionary alloc] init];
    }
    for (id key in stateInverseMap) {
        if (!inverseComplexCharMap[key]) {
            inverseComplexCharMap[key] = stateInverseMap[key];
        }
    }
    NSDictionary *imageMap = state[kScreenCharImageMapKey];
    AllocateImageMapsIfNeeded();
    for (id key in imageMap) {
        gEncodableImageMap[key] = imageMap[key];
        iTermImageInfo *info = [[[iTermImageInfo alloc] initWithDictionary:imageMap[key]] autorelease];
        if (info) {
            gImages[key] = info;
        }
    }
    ccmNextKey = [state[kScreenCharCCMNextKeyKey] intValue];
    hasWrapped = [state[kScreenCharHasWrappedKey] boolValue];
}
