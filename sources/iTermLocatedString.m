//
//  iTermLocatedString.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/20.
//

#import "iTermLocatedString.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermLocatedString {
    NSMutableString *_string;
@protected
    NSMutableArray<NSValue *> *_coords;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _string = [NSMutableString string];
        _coords = [NSMutableArray array];
    }
    return self;
}

- (void)appendString:(NSString *)string at:(VT100GridCoord)coord {
    [_string appendString:string];
    [self appendCoordsForString:string at:coord];
}

- (void)appendCoordsForString:(NSString *)string at:(VT100GridCoord)coord {
    const NSInteger length = string.length;
    NSValue *value = [NSValue valueWithGridCoord:coord];
    for (NSInteger i = 0; i < length; i++) {
        [_coords addObject:value];
    }
}

- (void)erase {
    _string = [NSMutableString string];
    _coords = [NSMutableArray array];
}

- (NSInteger)length {
    return _string.length;
}

- (void)dropFirst:(NSInteger)count {
    const NSRange range = NSMakeRange(0, count);
    [_string replaceCharactersInRange:range withString:@""];
    // TODO: Remove leading low surrogate
    [_coords removeObjectsInRange:range];
}

- (void)trimTrailingWhitespace {
    const NSInteger lengthBeforeTrimming = _string.length;
    [_string trimTrailingWhitespace];
    [_coords removeObjectsInRange:NSMakeRange(_string.length,
                                              lengthBeforeTrimming - _string.length)];
}

- (void)removeOcurrencesOfString:(NSString *)string {
    NSArray *empty = @[];
    [_string reverseEnumerateSubstringsEqualTo:string block:^(NSRange range) {
        [_string replaceCharactersInRange:range withString:@""];
        [_coords replaceObjectsInRange:range withObjectsFromArray:empty];
    }];
}

@end

@implementation iTermLocatedAttributedString {
    NSMutableAttributedString *_attributedString;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _attributedString = [[NSMutableAttributedString alloc] init];
    }
    return self;
}

- (NSString *)string {
    return _attributedString.string;
}

- (void)appendString:(NSString *)string
      withAttributes:(NSDictionary *)attributes
                  at:(VT100GridCoord)coord {
    [_attributedString iterm_appendString:string withAttributes:attributes];
    [self appendCoordsForString:string at:coord];
}

- (void)appendAttributedString:(NSAttributedString *)attributedString
                            at:(VT100GridCoord)coord {
    [_attributedString appendAttributedString:attributedString];
    [self appendCoordsForString:attributedString.string at:coord];
}

- (void)erase {
    [super erase];
    _attributedString = [[NSMutableAttributedString alloc] init];
}

- (NSInteger)length {
    return _attributedString.length;
}

- (void)dropFirst:(NSInteger)count {
    const NSRange range = NSMakeRange(0, count);
    [_attributedString replaceCharactersInRange:range withString:@""];
    // TODO: Remove leading low surrogate
    [_coords removeObjectsInRange:range];
}

- (void)trimTrailingWhitespace {
    const NSInteger lengthBeforeTrimming = _attributedString.length;
    [_attributedString trimTrailingWhitespace];
    [_coords removeObjectsInRange:NSMakeRange(_attributedString.length,
                                              lengthBeforeTrimming - _attributedString.length)];
}

- (void)removeOcurrencesOfString:(NSString *)string {
    NSArray *empty = @[];
    [_attributedString.string reverseEnumerateSubstringsEqualTo:string block:^(NSRange range) {
        [_attributedString replaceCharactersInRange:range withString:@""];
        [_coords replaceObjectsInRange:range withObjectsFromArray:empty];
    }];
}

@end
