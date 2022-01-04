//
//  VT100ScreenConfiguration.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100ScreenConfiguration.h"
#import "NSArray+iTerm.h"

@interface VT100ScreenConfiguration()
@property (nonatomic, readwrite) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readwrite) NSString *sessionGuid;
@property (nonatomic, readwrite) BOOL treatAmbiguousCharsAsDoubleWidth;
@property (nonatomic, readwrite) NSInteger unicodeVersion;
@end

@implementation VT100ScreenConfiguration

@synthesize shouldPlacePromptAtFirstColumn = _shouldPlacePromptAtFirstColumn;
@synthesize sessionGuid = _sessionGuid;
@synthesize treatAmbiguousCharsAsDoubleWidth = _treatAmbiguousCharsAsDoubleWidth;
@synthesize unicodeVersion = _unicodeVersion;

- (instancetype)initFrom:(VT100ScreenConfiguration *)other {
    self = [super init];
    if (self) {
        _shouldPlacePromptAtFirstColumn = other.shouldPlacePromptAtFirstColumn;
        _sessionGuid = other.sessionGuid;
        _treatAmbiguousCharsAsDoubleWidth = other.treatAmbiguousCharsAsDoubleWidth;
        _unicodeVersion = other.unicodeVersion;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)description {
    NSDictionary *dict = @{ @"shouldPlacePromptAtFirstColumn": @(_shouldPlacePromptAtFirstColumn),
                            @"sessionGuid": _sessionGuid ?: @"(nil)",
                            @"treatAmbiguousCharsAsDoubleWidth": @(_treatAmbiguousCharsAsDoubleWidth),
                            @"unicodeVersion": @(_unicodeVersion),
    };
    NSArray<NSString *> *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *kvps = [keys mapWithBlock:^id(NSString *key) {
        return [NSString stringWithFormat:@"    %@=%@", key, dict[key]];
    }];
    NSString *values = [kvps componentsJoinedByString:@"\n"];
    return [NSString stringWithFormat:@"<%@: %p\n%@>", NSStringFromClass([self class]), self, values];
}
@end

@implementation VT100MutableScreenConfiguration

@dynamic shouldPlacePromptAtFirstColumn;
@dynamic sessionGuid;
@dynamic treatAmbiguousCharsAsDoubleWidth;
@dynamic unicodeVersion;

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100ScreenConfiguration alloc] initFrom:self];
}

@end

