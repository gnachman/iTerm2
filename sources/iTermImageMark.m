//
//  iTermImageMark.m
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermImageMark.h"
#import "ScreenChar.h"

@implementation iTermImageMark

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _imageCode = dict[@"imageCode"];
        if (!_imageCode) {
            return nil;
        }
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    if (_imageCode) {
        return @{ @"imageCode": _imageCode };
    } else {
        return @{};
    }
}

- (void)dealloc {
    if (_imageCode) {
        ReleaseImage(_imageCode.integerValue);
    }
}

@end
