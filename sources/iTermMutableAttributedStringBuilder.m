//
//  iTermMutableAttributedStringBuilder.m
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import "iTermMutableAttributedStringBuilder.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSDictionary+iTerm.h"

#warning Use a dynamically sized buffer to avoid wasting memory. Never stop because you hit the max size.
#define MAX_CHARACTERS 300

@interface iTermCheapAttributedString()
@property (nonatomic, assign) unichar *characters;
@property (assign) NSUInteger length;
@property (nonatomic, retain) NSDictionary *attributes;
@end

@implementation iTermCheapAttributedString

- (void)dealloc {
    [_attributes release];
    [super dealloc];
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
    unichar _characters[MAX_CHARACTERS];
    NSInteger _numCharacters;
    BOOL _canUseFastPath;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _string = [[NSMutableString alloc] init];
#if ENABLE_TEXT_DRAWING_FAST_PATH
        _canUseFastPath = YES;
#endif
    }
    return self;
}

- (void)dealloc {
    [_attributedString release];
    [_attributes release];
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
    if (_canUseFastPath && !_attributedString && _numCharacters && !_string.length) {
        iTermCheapAttributedString *cheap = [[iTermCheapAttributedString alloc] init];
        cheap.characters = _characters;
        cheap.length = _numCharacters;
        cheap.attributes = _attributes;
        _attributedString = cheap;
        return;
    }
    if (_numCharacters) {
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
    _canUseFastPath = NO;
    if (_numCharacters) {
        [self flushCharacters];
    }
    [_string appendString:string];
}

- (void)flushCharacters {
    [_string appendString:[NSString stringWithCharacters:_characters length:_numCharacters]];
    _canUseFastPath = NO;
    _numCharacters = 0;
}

- (void)appendCharacter:(unichar)code {
    _canUseFastPath &= iTermCharacterSupportsFastPath(code, _asciiLigaturesAvailable);
    if (_numCharacters == MAX_CHARACTERS) {
        [self flushCharacters];
    }
    _characters[_numCharacters++] = code;
}

- (NSInteger)length {
    return _string.length + _attributedString.length + _numCharacters;
}

@end

@implementation NSMutableAttributedString(iTermMutableAttributedStringBuilder)

- (void)addAttribute:(NSString *)name value:(id)value {
    [self addAttribute:name value:value range:NSMakeRange(0, self.length)];
}

@end
