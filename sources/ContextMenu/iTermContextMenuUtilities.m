//
//  iTermContextMenuUtilities.m
//  iTerm2
//
//  Created by George Nachman on 6/30/25.
//

#import "iTermContextMenuUtilities.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import "iTerm2SharedARC-Swift.h"

@implementation NSString(ContextMenu)

- (NSArray<iTermTuple<NSString *, NSString *> *> *)helpfulSynonyms {
    NSMutableArray *array = [NSMutableArray array];
    iTermTuple<NSString *, NSString *> *hexOrDecimalConversion = [self hexOrDecimalConversionHelp];
    if (hexOrDecimalConversion) {
        [array addObject:hexOrDecimalConversion];
    }
    iTermTuple<NSString *, NSString *> *scientificNotationConversion = [self scientificNotationConversionHelp];
    if (scientificNotationConversion) {
        [array addObject:scientificNotationConversion];
    }
    iTermTuple<NSString *, NSString *> *timestampConversion = [self timestampConversionHelp];
    if (timestampConversion) {
        [array addObject:timestampConversion];
    }
    iTermTuple<NSString *, NSString *> *utf8Help = [self utf8Help];
    if (utf8Help) {
        [array addObject:utf8Help];
    }
    if (array.count) {
        return array;
    } else {
        return nil;
    }
}

- (iTermTuple<NSString *, NSString *> *)hexOrDecimalConversionHelp {
    unsigned long long value;
    BOOL mustBePositive = NO;
    BOOL decToHex;
    BOOL is32bit;
    if ([self hasPrefix:@"0x"] && [self length] <= 18) {
        decToHex = NO;
        NSScanner *scanner = [NSScanner scannerWithString:self];
        [scanner setScanLocation:2]; // bypass 0x
        if (![scanner scanHexLongLong:&value]) {
            return nil;
        }
        is32bit = [self length] <= 10;
    } else {
        if (![[self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isNumeric]) {
            return nil;
        }
        decToHex = YES;
        NSDecimalNumber *temp = [NSDecimalNumber decimalNumberWithString:self];
        if ([temp isEqual:[NSDecimalNumber notANumber]]) {
            return nil;
        }
        NSDecimalNumber *smallestSignedLongLong =
            [NSDecimalNumber decimalNumberWithString:@"-9223372036854775808"];
        NSDecimalNumber *largestUnsignedLongLong =
            [NSDecimalNumber decimalNumberWithString:@"18446744073709551615"];
        if ([temp doubleValue] > 0) {
            if ([temp compare:largestUnsignedLongLong] == NSOrderedDescending) {
                return nil;
            }
            mustBePositive = YES;
            is32bit = ([temp compare:@2147483648LL] == NSOrderedAscending);
        } else if ([temp compare:smallestSignedLongLong] == NSOrderedAscending) {
            // Negative but smaller than a signed 64 bit can hold
            return nil;
        } else {
            // Negative but fits in signed 64 bit
            is32bit = ([temp compare:@-2147483649LL] == NSOrderedDescending);
        }
        value = [temp unsignedLongLongValue];
    }

    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;

    NSString *humanReadableSize = [NSString stringWithHumanReadableSize:value];
    if (value >= 1024) {
        humanReadableSize = [NSString stringWithFormat:@" (%@)", humanReadableSize];
    } else {
        humanReadableSize = @"";
    }

    if (is32bit) {
        // Value fits in a signed 32-bit value, so treat it as such
        int intValue =
        (int)value;
        NSString *formattedDecimalValue = [numberFormatter stringFromNumber:@(intValue)];
        if (decToHex) {
            if (intValue < 0) {
                humanReadableSize = @"";
            }
            NSString *converted = [NSString stringWithFormat:@"0x%x%@", intValue, humanReadableSize];
            NSString *display = [NSString stringWithFormat:@"%@ = %@",
                                 formattedDecimalValue, converted];
            return [iTermTuple tupleWithObject:display andObject:converted];
        } else if (intValue >= 0) {
            NSString *converted = [NSString stringWithFormat:@"%@%@",
                                   formattedDecimalValue, humanReadableSize];
            NSString *display = [NSString stringWithFormat:@"0x%x = %@%@",
                                 intValue, formattedDecimalValue, humanReadableSize];
            return [iTermTuple tupleWithObject:display andObject:converted];
        } else {
            unsigned int unsignedIntValue = (unsigned int)value;
            NSString *formattedUnsignedDecimalValue =
                [numberFormatter stringFromNumber:@(unsignedIntValue)];
            NSString *converted = formattedDecimalValue;
            NSString *display = [NSString stringWithFormat:@"0x%x = %@ or %@%@",
                                 intValue, formattedDecimalValue, formattedUnsignedDecimalValue,
                                 humanReadableSize];
            return [iTermTuple tupleWithObject:display andObject:converted];
        }
    } else {
        // 64-bit value
        NSDecimalNumber *decimalNumber;
        long long signedValue = value;
        if (!mustBePositive && signedValue < 0) {
            decimalNumber = [NSDecimalNumber decimalNumberWithMantissa:-signedValue
                                                              exponent:0
                                                            isNegative:YES];
        } else {
            decimalNumber = [NSDecimalNumber decimalNumberWithMantissa:value
                                                              exponent:0
                                                            isNegative:NO];
        }
        NSString *formattedDecimalValue = [numberFormatter stringFromNumber:decimalNumber];
        if (decToHex) {
            if (!mustBePositive && signedValue < 0) {
                humanReadableSize = @"";
            }
            NSString *converted = [NSString stringWithFormat:@"0x%llx%@", value, humanReadableSize];
            NSString *display = [NSString stringWithFormat:@"%@ = 0x%llx%@",
                                 formattedDecimalValue, value, humanReadableSize];
            return [iTermTuple tupleWithObject:display andObject:converted];
        } else if (signedValue >= 0) {
            NSString *converted = [NSString stringWithFormat:@"%@%@",
                                   formattedDecimalValue, humanReadableSize];
            NSString *display = [NSString stringWithFormat:@"0x%llx = %@%@",
                                 value, formattedDecimalValue, humanReadableSize];
            return [iTermTuple tupleWithObject:display andObject:converted];
        } else {
            // Value is negative and converting hex to decimal.
            NSDecimalNumber *unsignedDecimalNumber =
                [NSDecimalNumber decimalNumberWithMantissa:value
                                                  exponent:0
                                                isNegative:NO];
            NSString *formattedUnsignedDecimalValue =
                [numberFormatter stringFromNumber:unsignedDecimalNumber];
            NSString *converted = [NSString stringWithFormat:@"%@",
                                   formattedDecimalValue];
            NSString *display = [NSString stringWithFormat:@"0x%llx = %@ or %@%@",
                                 value, formattedDecimalValue, formattedUnsignedDecimalValue,
                                 humanReadableSize];
            return [iTermTuple tupleWithObject:display andObject:converted];
        }
    }
}

- (iTermTuple<NSString *, NSString *> *)scientificNotationConversionHelp {
    NSString *scientificNotationRegex = @"^-?(0|[1-9]\\d*)?(\\.\\d+)?[eE][+\\-]?\\d+$";
    const BOOL isScientificNotation = [self isMatchedByRegex:scientificNotationRegex];
    if (!isScientificNotation) {
        return nil;
    }

    NSDecimalNumber *number = [[NSDecimalNumber alloc] initWithString:self];
    if (!number || [number isEqual:[NSDecimalNumber notANumber]]) {
        return nil;
    }

    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    numberFormatter.maximumFractionDigits = 1000;
    NSString *formattedNumber = [numberFormatter stringFromNumber:number];

    return [iTermTuple tupleWithObject:[NSString stringWithFormat:@"%@ = %@", self, formattedNumber]
                             andObject:formattedNumber];
}

- (iTermTuple<NSString *, NSString *> *)timestampConversionHelp {
    NSDate *date;
    date = [self dateValueFromUnix];
    BOOL wasUnix = (date != nil);
    if (!date) {
        date = [self dateValueFromUTC];
    }
    if (date) {
        NSString *template;
        if (fmod(date.timeIntervalSince1970, 1) > 0.001) {
            template = @"yyyyMMMd j:mm:ss.SSS z";
        } else {
            template = @"yyyyMMMd j:mm:ss z";
        }
        NSLocale *currentLocale = [NSLocale currentLocale];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        NSString *dateFormat = [NSDateFormatter dateFormatFromTemplate:template
                                                               options:0
                                                                locale:currentLocale];
        [fmt setDateFormat:dateFormat];
        if (wasUnix) {
            return [iTermTuple tupleWithObject:[fmt stringFromDate:date]
                                     andObject:[fmt stringFromDate:date]];
        } else {
            return [iTermTuple tupleWithObject:[NSString stringWithFormat:@"Unix timestamp %@", @(date.timeIntervalSince1970)]
                                     andObject:[@(date.timeIntervalSince1970) stringValue]];
        }
    } else {
        return nil;
    }
}

- (iTermTuple<NSString *, NSString *> *)utf8Help {
    if (self.length == 0) {
        return nil;
    }

    CFRange graphemeClusterRange = CFStringGetRangeOfComposedCharactersAtIndex((CFStringRef)self, 0);
    if (graphemeClusterRange.location != 0 ||
        graphemeClusterRange.length != self.length) {
        // Only works for a single grapheme cluster.
        return nil;
    }

    if ([self characterAtIndex:0] < 128 && self.length == 1) {
        // No help for ASCII
        return nil;
    }

    // Convert to UCS-4
    NSData *data = [self dataUsingEncoding:NSUTF32StringEncoding];
    const int *characters = (int *)data.bytes;
    int numCharacters = data.length / 4;

    // Output UTF-8 hex codes
    NSMutableArray *byteStrings = [NSMutableArray array];
    const char *utf8 = [self UTF8String];
    for (size_t i = 0; utf8[i]; i++) {
        [byteStrings addObject:[NSString stringWithFormat:@"0x%02x", utf8[i] & 0xff]];
    }
    NSString *utf8String = [byteStrings componentsJoinedByString:@" "];

    // Output UCS-4 hex codes
    NSMutableArray *ucs4Strings = [NSMutableArray array];
    for (NSUInteger i = 0; i < numCharacters; i++) {
        if (characters[i] == 0xfeff) {
            // Ignore byte order mark
            continue;
        }
        [ucs4Strings addObject:[NSString stringWithFormat:@"U+%04x", characters[i]]];
    }
    NSString *ucs4String = [ucs4Strings componentsJoinedByString:@" "];

    return [iTermTuple tupleWithObject:[NSString stringWithFormat:@"“%@” = %@ = %@ (UTF-8)", self, ucs4String, utf8String]
                             andObject:utf8String];
}

- (NSDate *)dateValueFromUnix {
    typedef struct {
        NSString *regex;
        double divisor;
    } Format;
    // TODO: Change these regexes to begin with ^[12] in the year 2032 or so.
    Format formats[] = {
        {
            .regex = @"^1[0-9]{9}$",
            .divisor = 1
        },
        {
            .regex = @"^1[0-9]{12}$",
            .divisor = 1000
        },
        {
            .regex = @"^1[0-9]{15}$",
            .divisor = 1000000
        },
        {
            .regex = @"^1[0-9]{9}\\.[0-9]+$",
            .divisor = 1
        }
    };
    for (size_t i = 0; i < sizeof(formats) / sizeof(*formats); i++) {
        if ([self isMatchedByRegex:formats[i].regex]) {
            const NSTimeInterval timestamp = [self doubleValue] / formats[i].divisor;
            return [NSDate dateWithTimeIntervalSince1970:timestamp];
        }
    }
    return nil;
}

- (NSDate *)dateValueFromUTC {
    NSArray<NSString *> *formats = @[ @"E, d MMM yyyy HH:mm:ss zzz",
                                      @"EEE MMM dd HH:mm:ss zzz yyyy",
                                      @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                                      @"yyyy-MM-dd't'HH:mm:ss.SSS'z'",
                                      @"yyyy-MM-dd'T'HH:mm:ss'Z'",
                                      @"yyyy-MM-dd't'HH:mm:ss'z'",
                                      @"yyyy-MM-dd'T'HH:mm'Z'",
                                      @"yyyy-MM-dd't'HH:mm'z'" ];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    for (NSString *format in formats) {
        dateFormatter.dateFormat = format;
        dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        NSDate *date = [dateFormatter dateFromString:self];
        if (date) {
            return date;
        }
    }
    return nil;
}
@end

@implementation iTermContextMenuUtilities

+ (BOOL)addMenuItemForColors:(NSString *)shortSelectedText menu:(NSMenu *)theMenu index:(NSInteger)i {
    NSArray *captures = [shortSelectedText captureComponentsMatchedByRegex:@"^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$"];
    if (captures.count) {
        NSMenuItem *theItem = [[NSMenuItem alloc] init];
        NSColor *color = [NSColor colorFromHexString:shortSelectedText];
        if (color) {
            CGFloat x;
            if (@available(macOS 10.16, *)) {
                x = 15;
            } else {
                x = 11;
            }
            const CGFloat margin = 2;
            const CGFloat height = 24;
            const CGFloat width = 24;
            NSView *wrapper = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width + x, height + margin * 2)];
            NSView *colorView = [[NSView alloc] initWithFrame:NSMakeRect(x, margin, width, height)];
            colorView.wantsLayer = YES;
            colorView.layer = [[CALayer alloc] init];
            colorView.layer.backgroundColor = [color CGColor];
            colorView.layer.borderColor = [color.isDark ? [NSColor colorWithWhite:0.8 alpha:1] : [NSColor colorWithWhite:0.2 alpha:1] CGColor];
            colorView.layer.borderWidth = 1;
            colorView.layer.cornerRadius = 3;
            wrapper.autoresizesSubviews = YES;
            colorView.autoresizingMask = NSViewMaxXMargin;
            [wrapper addSubview:colorView];
            theItem.view = wrapper;
            [theMenu insertItem:theItem atIndex:i];
            return YES;
        }
    }
    return NO;
}

+ (BOOL)addMenuItemForBase64Encoded:(NSString *)shortSelectedText menu:(NSMenu *)theMenu index:(NSInteger)i selector:(nonnull SEL)selector target:(id)target {
    if (shortSelectedText.mayBeBase64Encoded && shortSelectedText.length > 3) {
        NSData *decoded = [NSData dataWithBase64EncodedString:shortSelectedText];
        if (!decoded) {
            decoded = [NSData dataWithURLSafeBase64EncodedString:shortSelectedText];
        }
        if (decoded) {
            NSMenuItem *item = [[NSMenuItem alloc] init];
            item.title = [NSString stringWithFormat:@"Base64: %@", [[decoded humanFriendlyStringRepresentation] ellipsizedDescriptionNoLongerThan:20]];
            item.action = selector;
            item.target = target;
            item.representedObject = decoded;
            [theMenu insertItem:item atIndex:i];
            return YES;
        }
    }
    return NO;
}

static int32_t iTermInt32FromBytes(const unsigned char *bytes, BOOL bigEndian) {
    uint32_t i;
    if (bigEndian) {
        i = ((((uint32_t)bytes[0]) << 24) |
             (((uint32_t)bytes[1]) << 16) |
             (((uint32_t)bytes[2]) << 8) |
             (((uint32_t)bytes[3]) << 0));
    } else {
        i = ((((uint32_t)bytes[3]) << 24) |
             (((uint32_t)bytes[2]) << 16) |
             (((uint32_t)bytes[1]) << 8) |
             (((uint32_t)bytes[0]) << 0));
    }
    return i;
}

static uint64_t iTermInt64FromBytes(const unsigned char *bytes, BOOL bigEndian) {
    uint64_t i;
    if (bigEndian) {
        i = ((((uint64_t)bytes[0]) << 56) |
             (((uint64_t)bytes[1]) << 48) |
             (((uint64_t)bytes[2]) << 40) |
             (((uint64_t)bytes[3]) << 32) |
             (((uint64_t)bytes[4]) << 24) |
             (((uint64_t)bytes[5]) << 16) |
             (((uint64_t)bytes[6]) << 8) |
             (((uint64_t)bytes[7]) << 0));
    } else {
        i = ((((uint64_t)bytes[7]) << 56) |
             (((uint64_t)bytes[6]) << 48) |
             (((uint64_t)bytes[5]) << 40) |
             (((uint64_t)bytes[4]) << 32) |
             (((uint64_t)bytes[3]) << 24) |
             (((uint64_t)bytes[2]) << 16) |
             (((uint64_t)bytes[1]) << 8) |
             (((uint64_t)bytes[0]) << 0));
    }
    return i;
}

+ (NSInteger)addMenuItemsForNumericConversions:(NSString *)text menu:(NSMenu *)theMenu index:(NSInteger)i selector:(SEL)selector target:(id)target {
    NSInteger index = i;
    NSData *data = [text dataFromWhitespaceDelimitedHexValues];
    if (data.length > 0) {
        NSMenuItem *theItem = nil;
        if (data.length > 1) {
            if (data.length == 4) {
                const uint32_t be = iTermInt32FromBytes(data.bytes, YES);
                theItem = [[NSMenuItem alloc] init];
                theItem.title = [NSString stringWithFormat:@"Big-Endian int32: %@", @(be)];
                theItem.target = self;
                theItem.action = selector;
                theItem.target = target;
                theItem.representedObject = [@(be) stringValue];
                [theMenu insertItem:theItem atIndex:index++];

                const uint32_t le = iTermInt32FromBytes(data.bytes, NO);
                theItem = [[NSMenuItem alloc] init];
                theItem.title = [NSString stringWithFormat:@"Little-Endian int32: %@", @(le)];
                theItem.target = self;
                theItem.action = selector;
                theItem.target = target;
                theItem.representedObject = [@(le) stringValue];
                [theMenu insertItem:theItem atIndex:index++];
            } else if (data.length == 8) {
                const uint64_t be = iTermInt64FromBytes(data.bytes, YES);
                theItem = [[NSMenuItem alloc] init];
                theItem.title = [NSString stringWithFormat:@"Big-Endian int64: %@", @(be)];
                theItem.target = self;
                theItem.action = selector;
                theItem.target = target;
                theItem.representedObject = [@(be) stringValue];
                [theMenu insertItem:theItem atIndex:index++];

                const uint64_t le = iTermInt64FromBytes(data.bytes, NO);
                theItem = [[NSMenuItem alloc] init];
                theItem.title = [NSString stringWithFormat:@"Little-Endian int64: %@", @(le)];
                theItem.target = self;
                theItem.action = selector;
                theItem.target = target;
                theItem.representedObject = [@(le) stringValue];
                [theMenu insertItem:theItem atIndex:index++];
            } else if (data.length < 100) {
                NSString *stringValue = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (stringValue) {
                    theItem = [[NSMenuItem alloc] init];
                    theItem.title = [NSString stringWithFormat:@"%@ UTF-8 bytes: %@", @(data.length), stringValue];
                    theItem.target = self;
                    theItem.action = selector;
                    theItem.target = target;
                    theItem.representedObject = stringValue;
                    [theMenu insertItem:theItem atIndex:index++];
                }
            }
            if (!theItem && data.length > 4) {
                theItem = [[NSMenuItem alloc] init];
                theItem.title = [NSString stringWithFormat:@"%@ hex bytes", @(data.length)];
                [theMenu insertItem:theItem atIndex:index++];
            }
        }
    }
    return index;
}

+ (NSInteger)addMenuItemsToCopyBase64:(NSString *)text
                                 menu:(NSMenu *)theMenu
                                index:(NSInteger)i
                             selectorForString:(SEL)selectorForString
                      selectorForData:(SEL)selectorForData
                               target:(id _Nullable)target {
    NSInteger index = i;

    if (text.mayBeBase64Encoded) {
        NSData *decoded = [NSData dataWithBase64EncodedString:text];
        if (!decoded) {
            decoded = [NSData dataWithURLSafeBase64EncodedString:text];
        }
        if (decoded) {
            NSMenuItem *item = [[NSMenuItem alloc] init];
            item.title = @"Copy Base64-Decoded";
            item.action = selectorForData;
            item.target = target;
            item.representedObject = decoded;
            [theMenu insertItem:item atIndex:index++];
        }
    }
    NSString *encoded = [[text dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:NSDataBase64Encoding76CharacterLineLength];
    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.title = @"Copy Base64-Encoded";
    item.target = target;
    item.action = selectorForString;
    item.representedObject = encoded;
    [theMenu insertItem:item atIndex:index++];

    return index;
}

@end
