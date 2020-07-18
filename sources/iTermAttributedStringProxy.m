//
//  iTermAttributedStringProxy.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/16/20.
//

#import "iTermAttributedStringProxy.h"
#import "NSObject+iTerm.h"

#import <Cocoa/Cocoa.h>

@interface iTermAttributedStringProxy()
@property (nonatomic, copy) NSString *string;
@end

@implementation iTermAttributedStringProxy {
    NSUInteger _hash;
    NSUInteger _ligature;
    NSFont *_font;
}

+ (instancetype)withAttributedString:(NSAttributedString *)attributedString {
    return [[self alloc] initWithAttributedString:attributedString];
}

- (instancetype)initWithAttributedString:(NSAttributedString *)attributedString {
    self = [super init];
    if (self) {
        NSDictionary *attributes = [attributedString attributesAtIndex:0 effectiveRange:nil];
        self.string = attributedString.string;
        _hash = iTermCombineHash(iTermCombineHash(self.string.hash, _ligature), _font.hash);
        _ligature = [attributes[(__bridge NSString *)kCTLigatureAttributeName] unsignedIntegerValue];
        _font = attributes[(__bridge NSString *)kCTFontAttributeName];
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (object == nil) {
        return NO;
    }
    if (object == self) {
        return YES;
    }
    iTermAttributedStringProxy *other = [iTermAttributedStringProxy castFrom:object];
    return ([other.string isEqual:self.string] &&
            other->_ligature == _ligature &&
            [other->_font isEqual:_font]);
}

- (NSUInteger)hash {
    return _hash;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end
