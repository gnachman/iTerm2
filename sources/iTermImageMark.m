//
//  iTermImageMark.m
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermImageMark.h"

#import "DebugLogging.h"
#import "ScreenChar.h"

@implementation iTermImageMark

- (instancetype)init {
    self = [super init];
    DLog(@"New mage mark %@ created", self);
    return self;
}

- (void)setImageCode:(NSNumber *)imageCode {
    _imageCode = imageCode;
    DLog(@"Update image code %@", self);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@>", self.class, self, self.imageCode];
}

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
    DLog(@"Deallocing %@", self);
    if (_imageCode) {
        ReleaseImage(_imageCode.integerValue);
    }
}

@end
