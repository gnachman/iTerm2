//
//  iTermURLMark.m
//  iTerm2
//
//  Created by George Nachman on 4/1/17.
//
//

#import "iTermURLMark.h"
#import "iTermURLStore.h"

@implementation iTermURLMark

- (instancetype)initWithCode:(unsigned int)code {
    self = [super init];
    if (self) {
        [[iTermURLStore sharedInstance] retainCode:code];
        _code = code;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    return [self initWithCode:[dict[@"code"] unsignedIntValue]];
}

- (NSDictionary *)dictionaryValue {
    return @{ @"code": @(_code) };
}

- (NSString *)shortDebugDescription {
    return [NSString stringWithFormat:@"[URL %@]", [[iTermURLStore sharedInstance] urlForCode:_code]];
}

- (void)dealloc {
    if (_code) {
        [[iTermURLStore sharedInstance] releaseCode:_code];
    }
}

@end
