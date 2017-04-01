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

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _code = [dict[@"code"] unsignedShortValue];
        // We trust that the iTermURLStore will be restored along with the refcounts.
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    return @{ @"code": @(_code) };
}

- (void)setCode:(unsigned short)code {
    if (code == _code) {
        return;
    }
    if (_code) {
        [[iTermURLStore sharedInstance] releaseCode:_code];
    }
    if (code) {
        [[iTermURLStore sharedInstance] retainCode:code];
    }
    _code = code;
}

- (void)dealloc {
    if (_code) {
        [[iTermURLStore sharedInstance] releaseCode:_code];
    }
}

@end
