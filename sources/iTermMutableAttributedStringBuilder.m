//
//  iTermMutableAttributedStringBuilder.m
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import "iTermMutableAttributedStringBuilder.h"
#import "NSMutableAttributedString+iTerm.h"

#define MAX_CHARACTERS 100

@implementation iTermMutableAttributedStringBuilder {
    NSMutableAttributedString *_attributedString;
    NSMutableString *_string;
    unichar _characters[MAX_CHARACTERS];
    NSInteger _numCharacters;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _attributedString = [[NSMutableAttributedString alloc] init];
        [_attributedString beginEditing];
        _string = [[NSMutableString alloc] init];
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
    if (_numCharacters) {
        [self flushCharacters];
    }
    if (_string.length) {
        [_attributedString appendAttributedString:[NSAttributedString attributedStringWithString:_string
                                                                                      attributes:_attributes]];
        [_string setString:@""];
    }
}
- (NSMutableAttributedString *)attributedString {
    [self build];
    [_attributedString endEditing];
    return _attributedString;
}

- (void)appendString:(NSString *)string {
    if (_numCharacters) {
        [self flushCharacters];
    }
    [_string appendString:string];
}

- (void)flushCharacters {
    [_string appendString:[NSString stringWithCharacters:_characters length:_numCharacters]];
    _numCharacters = 0;
}

- (void)appendCharacter:(unichar)code {
    if (_numCharacters == MAX_CHARACTERS) {
        [self flushCharacters];
    }
    _characters[_numCharacters++] = code;
}

- (NSInteger)length {
    return _string.length + _attributedString.length + _numCharacters;
}

@end
