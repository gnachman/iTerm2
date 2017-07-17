//
//  iTermMutableAttributedStringBuilder.m
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import "iTermMutableAttributedStringBuilder.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSDictionary+iTerm.h"

@interface iTermCheapAttributedString()
@property (nonatomic, retain) NSMutableData *characterData;
@property (nonatomic, retain) NSDictionary *attributes;
@end

@implementation iTermCheapAttributedString

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>",
	   NSStringFromClass([self class]),
	   self,
	   [[[NSString alloc] initWithCharacters:[self characters] length:[self length]] autorelease]];
}

- (void)dealloc {
    [_attributes release];
    [_characterData release];
    [super dealloc];
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

@end

@implementation iTermMutableAttributedStringBuilder {
    id<iTermAttributedString> _attributedString;
    NSMutableString *_string;
    NSMutableData *_characterData;
    BOOL _canUseFastPath;
}

- (instancetype)init {
    self = [super init];
    if (self) {
#if ENABLE_TEXT_DRAWING_FAST_PATH
        _canUseFastPath = YES;
#endif
    }
    return self;
}

- (void)dealloc {
    [_attributedString release];
    [_attributes release];
    [_characterData release];
    [_string release];
    [super dealloc];
}

- (void)setAttributes:(NSDictionary *)attributes {
    if ([attributes isEqualToDictionary:_attributes]) {
        return;
    }
    [self build];
    [_attributes release];
    _attributes = [attributes copy];
}

- (void)build {
    if (_canUseFastPath && !_attributedString && _characterData.length / sizeof(unichar) && !_string.length) {
        iTermCheapAttributedString *cheap = [[iTermCheapAttributedString alloc] init];
        cheap.characterData = _characterData;
        cheap.attributes = _attributes;
        _attributedString = cheap;
        return;
    } else if ([_attributedString isKindOfClass:[iTermCheapAttributedString class]]) {
        [_attributedString release];
        _attributedString = nil;
    }
    if (_characterData.length > 0) {
        [self flushCharacters];
    }
    if (_string.length) {
        _canUseFastPath = NO;
        if (!_attributedString) {
            _attributedString = [[NSMutableAttributedString alloc] init];
            [_attributedString beginEditing];
        }
        [_attributedString appendAttributedString:[NSAttributedString attributedStringWithString:_string
                                                                                      attributes:_attributes]];
        [_string setString:@""];
    }
}
- (id<iTermAttributedString>)attributedString {
    [self build];
    if ([_attributedString isKindOfClass:[NSAttributedString class]]) {
        [_attributedString endEditing];
    }
    return _attributedString;
}

- (void)appendString:(NSString *)string {
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
            [self appendCharacter:c];
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
    [_string appendString:string];
}

- (void)flushCharacters {
    if (!_string) {
        _string = [[NSMutableString alloc] init];
    }
    [_string appendString:[NSString stringWithCharacters:_characterData.mutableBytes length:_characterData.length / sizeof(unichar)]];
    _canUseFastPath = NO;
    [_characterData release];
    _characterData = nil;
}

- (void)appendCharacter:(unichar)code {
    if (!_zippy) {
        _canUseFastPath &= iTermCharacterSupportsFastPath(code, _asciiLigaturesAvailable);
    }
    if (!_characterData) {
        _characterData = [[NSMutableData alloc] init];
    }
    [_characterData appendBytes:&code length:sizeof(unichar)];
}

- (NSInteger)length {
    return _string.length + _attributedString.length + _characterData.length / sizeof(unichar);
}

- (void)disableFastPath {
    _canUseFastPath = NO;
}

@end

@implementation NSMutableAttributedString(iTermMutableAttributedStringBuilder)

- (void)addAttribute:(NSString *)name value:(id)value {
    [self addAttribute:name value:value range:NSMakeRange(0, self.length)];
}

@end
