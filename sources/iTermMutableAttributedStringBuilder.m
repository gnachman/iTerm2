//
//  iTermMutableAttributedStringBuilder.m
//  iTerm2
//
//  Created by George Nachman on 7/13/16.
//
//

#import "iTermMutableAttributedStringBuilder.h"
#import "NSMutableAttributedString+iTerm.h"

#define ENABLE_THREADED_BUILD 1

#define MAX_CHARACTERS 100
static dispatch_queue_t gQueue;

@implementation iTermMutableAttributedStringBuilder {
    NSMutableAttributedString *_attributedString;
    NSMutableString *_string;
    unichar _characters[MAX_CHARACTERS];
    NSInteger _numCharacters;
    dispatch_group_t _group;
    CTLineRef _lineRef;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gQueue = dispatch_queue_create("com.googlecode.iterm2.AttributedStringBuilder", DISPATCH_QUEUE_CONCURRENT);
        });
        _group = dispatch_group_create();
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
    if (_lineRef) {
        CFRelease(_lineRef);
    }
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
    @synchronized (self) {
        if (_numCharacters) {
            [self flushCharacters];
        }
        if (_string.length) {
            [_attributedString appendAttributedString:[NSAttributedString attributedStringWithString:_string
                                                                                          attributes:_attributes]];
            [_string setString:@""];
        }
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

#if ENABLE_THREADED_BUILD
- (void)buildAsynchronously:(void (^)())completion {
    dispatch_group_enter(_group);
    dispatch_async(gQueue, ^{
        if (_numCharacters > 0 || _string.length > 0) {
            [self build];
        }
        _lineRef = CTLineCreateWithAttributedString(self.attributedString);
        dispatch_group_leave(_group);
        if (completion) {
            completion();
        }
    });
}
- (CTLineRef)lineRef {
    dispatch_group_wait(_group, DISPATCH_TIME_FOREVER);
    return _lineRef;
}
#else
- (void)buildAsynchronously:(void (^)())completion {
    [self build];
    completion();
}
- (CTLineRef)lineRef {
    if (!_lineRef) {
        _lineRef = CTLineCreateWithAttributedString((CFAttributedStringRef)self.attributedString);
    }
    return _lineRef;
}
#endif

@end
