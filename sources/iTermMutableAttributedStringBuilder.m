//
//  iTermMutableAttributedStringBuilder.m
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import "iTermMutableAttributedStringBuilder.h"
#import "iTermAdvancedSettingsModel.h"
#import "CVector.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

NSString *const iTermSourceColumnsAttribute = @"iTermSourceColumnsAttribute";
NSString *const iTermSourceCellIndexAttribute = @"iTermSourceCellIndexAttribute";
NSString *const iTermDrawInCellIndexAttribute = @"iTermDrawInCellIndexAttribute";

@interface iTermCheapAttributedString()
@property (nonatomic, strong) NSMutableData *characterData;
@property (nonatomic, strong) NSDictionary *attributes;
@end

@implementation iTermCheapAttributedString

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>",
	   NSStringFromClass([self class]),
	   self,
	   [[NSString alloc] initWithCharacters:[self characters] length:[self length]]];
}

- (unichar *)characters {
    return _characterData.mutableBytes;
}

- (NSUInteger)length {
    return _characterData.length / sizeof(unichar);
}

- (void)addAttribute:(NSString *)name value:(id)value {
    self.attributes = [self.attributes dictionaryBySettingObject:value forKey:name];
}

- (void)beginEditing {
    [self doesNotRecognizeSelector:_cmd];
}

- (void)endEditing {
    [self doesNotRecognizeSelector:_cmd];
}

- (void)appendAttributedString:(NSAttributedString *)attrString {
    [self doesNotRecognizeSelector:_cmd];
}

- (iTermCheapAttributedString *)copyWithAttributes:(NSDictionary *)attributes {
    iTermCheapAttributedString *other = [[iTermCheapAttributedString alloc] init];
    other.characterData = [_characterData mutableCopy];
    other.attributes = attributes;
    return other;
}

- (NSRange)sourceColumnRange {
    return [[NSValue castFrom:_attributes[iTermSourceColumnsAttribute]] rangeValue];
}

@end

@implementation iTermMutableAttributedStringBuilder {
    id<iTermAttributedString> _attributedString;
    NSMutableString *_string;
    NSMutableData *_characterData;
    BOOL _canUseFastPath;
    BOOL _explicitDirectionControls;
    NSMutableIndexSet *_rtlIndexes;
    CTVector(int) _characterIndexToSourceCell;
    CTVector(int) _characterIndexToDrawCell;
    int _count;  // number of cells
}

- (instancetype)init {
    self = [super init];
    if (self) {
#if ENABLE_TEXT_DRAWING_FAST_PATH
        _canUseFastPath = [iTermAdvancedSettingsModel preferSpeedToFullLigatureSupport];
#endif
        _startColumn = _endColumn = NSNotFound;
        CTVectorCreate(&_characterIndexToSourceCell, 100);
        CTVectorCreate(&_characterIndexToDrawCell, 100);
    }
    return self;
}

- (void)dealloc {
    CTVectorDestroy(&_characterIndexToSourceCell);
    CTVectorDestroy(&_characterIndexToDrawCell);
}

- (void)setAttributes:(NSDictionary *)attributes {
    if ([attributes isEqualToDictionary:_attributes]) {
        return;
    }
    [self build];
    _attributes = [attributes copy];
}

- (void)setEndColumn:(NSInteger)endColumn {
    _endColumn = endColumn;
    NSValue *value = [NSValue valueWithRange:NSMakeRange(_startColumn, _endColumn - _startColumn)];
    _attributes = [_attributes dictionaryBySettingObject:value
                                                  forKey:iTermSourceColumnsAttribute];
}

- (BOOL)willCreateCheap {
    return (_canUseFastPath && !_attributedString && _characterData.length / sizeof(unichar) && !_string.length);
}

- (BOOL)didCreateCheap {
    return ([_attributedString isKindOfClass:[iTermCheapAttributedString class]]);
}

- (void)build {
    if (self.willCreateCheap) {
        // Create a cheap attributed string from character array
        iTermCheapAttributedString *cheap = [[iTermCheapAttributedString alloc] init];
        cheap.characterData = _characterData;
        cheap.attributes = _attributes;
        _attributedString = cheap;
        return;
    } else if (self.didCreateCheap) {
        // Convert a cheap attributed string to a real attributed string
        iTermCheapAttributedString *cheap = (id)_attributedString;
        _attributedString = nil;
        [self appendRealAttributedStringWithText:[NSString stringWithCharacters:cheap.characters length:cheap.length]
                                      attributes:cheap.attributes];
        [_string setString:@""];
        [_characterData setLength:0];
    }
    if (_characterData.length > 0) {
        [self flushCharacters];
    }
    if (_string.length) {
        [self appendRealAttributedStringWithText:_string attributes:_attributes];
        [_string setString:@""];
    }
    if (_explicitDirectionControls && _attributedString != nil) {
        NSMutableAttributedString *attributedString = [NSMutableAttributedString castFrom:_attributedString];
        assert(attributedString != nil);
        NSMutableIndexSet *ltrIndexes = [NSMutableIndexSet indexSet];
        [ltrIndexes addIndexesInRange:NSMakeRange(0, attributedString.length)];
        [_rtlIndexes enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
            [attributedString addAttribute:NSWritingDirectionAttributeName value:@[@(NSWritingDirectionRightToLeft | NSWritingDirectionOverride)] range:range];
            [ltrIndexes removeIndexesInRange:range];
        }];
        [ltrIndexes enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
            [attributedString addAttribute:NSWritingDirectionAttributeName value:@[@(NSWritingDirectionLeftToRight | NSWritingDirectionOverride)] range:range];
        }];
    }
}

- (void)appendRealAttributedStringWithText:(NSString *)string attributes:(NSDictionary *)attributes {
    _canUseFastPath = NO;
    if (!_attributedString) {
        _attributedString = [[NSMutableAttributedString alloc] init];
        [_attributedString beginEditing];
    }
    [_attributedString appendAttributedString:[NSAttributedString attributedStringWithString:string
                                                                                  attributes:attributes]];
}

- (id<iTermAttributedString>)attributedString {
    NSData *data = CTVectorGetData(&_characterIndexToSourceCell);
    NSMutableDictionary *temp = [_attributes mutableCopy];
    temp[iTermSourceCellIndexAttribute] = data;

    data = CTVectorGetData(&_characterIndexToDrawCell);
    temp[iTermDrawInCellIndexAttribute] = data;

    _attributes = temp;

    [self build];
    if ([_attributedString isKindOfClass:[NSAttributedString class]]) {
        [_attributedString endEditing];
    }
    return _attributedString;
}

- (void)appendString:(NSString *)string rtl:(BOOL)rtl sourceCell:(int)sourceCell drawInCell:(int)drawInCell {
    // Require a string length of 1 to avoid using zippy for combining marks, which core graphics
    // renders poorly. Zippy still has value for using core graphics for nonascii uncombined characters.
    BOOL tryZippy = _zippy;
    if (tryZippy && ![iTermAdvancedSettingsModel lowFiCombiningMarks] && string.length > 1) {
        tryZippy = NO;
    }
    if (tryZippy) {
        NSInteger i;
        for (i = 0; i < string.length; i++) {
            unichar c = [string characterAtIndex:i];
            if (CFStringIsSurrogateHighCharacter(c)) {
                string = [string substringFromIndex:i];
                break;
            }
            [self appendCharacter:c rtl:rtl sourceCell:sourceCell drawInCell:drawInCell];
        }
        if (i == string.length) {
            return;
        }
    }
    _canUseFastPath = NO;
    if (_characterData.length > 0) {
        [self flushCharacters];
    }
    if (!_string) {
        _string = [[NSMutableString alloc] init];
    }
    if (rtl) {
        [_rtlIndexes addIndexesInRange:NSMakeRange(_string.length, string.length)];
    }
    [_string appendString:string];
    for (NSUInteger i = 0; i < string.length; i++) {
        CTVectorAppend(&_characterIndexToSourceCell, sourceCell);
        CTVectorAppend(&_characterIndexToDrawCell, drawInCell);
    }
    _count += 1;
}

// Moves characters from characterData to string.
- (void)flushCharacters {
    if (!_string) {
        _string = [[NSMutableString alloc] init];
    }
    [_string appendString:[NSString stringWithCharacters:_characterData.mutableBytes length:_characterData.length / sizeof(unichar)]];
    _canUseFastPath = NO;
    _characterData = nil;
}

- (void)appendCharacter:(unichar)code rtl:(BOOL)rtl sourceCell:(int)sourceCell drawInCell:(int)drawInCell {
    if (!_zippy) {
        _canUseFastPath &= iTermCharacterSupportsFastPath(code, _asciiLigaturesAvailable);
    }
    if (code >= 0xe000 && code <= 0xf8ff) {
        _canUseFastPath = NO;
    }
    if (!_characterData) {
        _characterData = [[NSMutableData alloc] initWithCapacity:20];
    }
    if (rtl) {
        [_rtlIndexes addIndex:_string.length + _characterData.length / sizeof(unichar)];
    }
    [_characterData appendBytes:&code length:sizeof(unichar)];
    CTVectorAppend(&_characterIndexToSourceCell, sourceCell);
    CTVectorAppend(&_characterIndexToDrawCell, drawInCell);
    _count += 1;
}

- (NSInteger)length {
    return _string.length + _attributedString.length + _characterData.length / sizeof(unichar);
}

- (void)disableFastPath {
    _canUseFastPath = NO;
}

- (void)enableExplicitDirectionControls {
    if (_explicitDirectionControls) {
        return;
    }
    [self disableFastPath];
    _explicitDirectionControls = YES;
    _rtlIndexes = [NSMutableIndexSet indexSet];
}

@end

@implementation NSMutableAttributedString(iTermMutableAttributedStringBuilder)

- (void)addAttribute:(NSString *)name value:(id)value {
    [self addAttribute:name value:value range:NSMakeRange(0, self.length)];
}

- (NSRange)sourceColumnRange {
    id value = [self attribute:iTermSourceColumnsAttribute atIndex:0 effectiveRange:nil];
    return [[NSValue castFrom:value] rangeValue];
}

@end
