//
//  iTermLocatedString.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/20.
//

#import "iTermLocatedString.h"
#import "iTerm2SharedARC-Swift.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermLocatedString {
    NSMutableString *_string;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _string = [NSMutableString string];
        _gridCoords = [[iTermGridCoordArray alloc] init];
    }
    return self;
}

- (instancetype)initWithString:(NSString *)string gridCoords:(iTermGridCoordArray *)gridCoords {
    self = [super init];
    if (self) {
        _string = [string mutableCopy];
        _gridCoords = [gridCoords mutableCopy];
    }
    return self;
}


- (void)appendLocatedString:(iTermLocatedString *)locatedString {
    [_string appendString:locatedString.string];
    [_gridCoords appendContentsOfArray:locatedString.gridCoords];
}

- (void)prependString:(NSString *)string at:(VT100GridCoord)coord {
    [_string insertString:string atIndex:0];
    [self prependCoordsForString:string at:coord];
}

- (void)appendString:(NSString *)string at:(VT100GridCoord)coord {
    [_string appendString:string];
    [self appendCoordsForString:string at:coord];
}

- (void)appendCoordsForString:(NSString *)string at:(VT100GridCoord)coord {
    const NSInteger length = string.length;
    [_gridCoords appendWithCoord:coord repeating:length];
}

- (void)prependCoordsForString:(NSString *)string at:(VT100GridCoord)coord {
    const NSInteger length = string.length;
    [_gridCoords prependWithCoord:coord repeating:length];
}

- (void)erase {
    _string = [NSMutableString string];
    [_gridCoords removeAll];
}

- (NSInteger)length {
    return _string.length;
}

- (void)dropFirst:(NSInteger)count {
    const NSRange range = NSMakeRange(0, count);
    [_string replaceCharactersInRange:range withString:@""];
    // TODO: Remove leading low surrogate
    [_gridCoords removeFirst:count];
}

- (void)trimTrailingWhitespace {
    const NSInteger lengthBeforeTrimming = _string.length;
    [_string trimTrailingWhitespace];
    [_gridCoords removeLast:lengthBeforeTrimming - _string.length];
}

- (void)removeOcurrencesOfString:(NSString *)string {
    [_string reverseEnumerateSubstringsEqualTo:string block:^(NSRange range) {
        [_string replaceCharactersInRange:range withString:@""];
        [_gridCoords removeRange:range];
    }];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)replacement {
    [_string replaceCharactersInRange:range withString:replacement];
    [_gridCoords resizeRange:range
                          to:NSMakeRange(range.location, replacement.length)];
}

- (NSInteger)offsetOfLineNumber:(int)lineNumber {
    if (lineNumber <= 0) {
        return 0;
    }

    const NSUInteger length = _string.length;
    NSUInteger offset = 0;
    int currentLine = 0;

    while (currentLine < lineNumber && offset < length) {
        NSRange range = [_string rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]
                                                 options:0
                                                   range:NSMakeRange(offset, length - offset)];
        if (range.location == NSNotFound) {
            return NSNotFound; // LineNumber exceeds total lines
        }

        offset = range.location + 1;
        currentLine += 1;
    }

    return (currentLine == lineNumber) ? offset : NSNotFound;
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
    [self.gridCoords removeRange:range];
}

- (void)trimTrailingWhitespace {
    const NSInteger lengthBeforeTrimming = _attributedString.length;
    [_attributedString trimTrailingWhitespace];
    [self.gridCoords removeLast:lengthBeforeTrimming - _attributedString.length];
}

- (void)removeOcurrencesOfString:(NSString *)string {
    [_attributedString.string reverseEnumerateSubstringsEqualTo:string block:^(NSRange range) {
        [_attributedString replaceCharactersInRange:range withString:@""];
        [self.gridCoords removeRange:range];
    }];
}

@end
