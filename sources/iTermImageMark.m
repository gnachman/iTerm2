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

@implementation iTermImageMark {
    iTermImageMark *_doppelganger;
    __weak iTermImageMark *_progenitor;
    BOOL _isDoppelganger;
}

- (instancetype)initWithImageCode:(NSNumber *)imageCode {
    self = [super init];
    if (self) {
        _imageCode = imageCode;
    }
    DLog(@"New mage mark %@ created", self);
    return self;
}

- (void)setImageCode:(NSNumber *)imageCode {
    _imageCode = imageCode;
    DLog(@"Update image code %@", self);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p imageCode=%@ %@>",
            NSStringFromClass(self.class),
            self,
            self.imageCode,
            _isDoppelganger ? @"IsDop" : @"NotDop"];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    NSNumber *imageCode = dict[@"imageCode"];
    if (!imageCode) {
        return nil;
    }
    return [self initWithImageCode:imageCode];
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

- (id<IntervalTreeObject>)doppelganger {
    @synchronized ([iTermImageMark class]) {
        assert(!_isDoppelganger);
        if (!_doppelganger) {
            _doppelganger = [[iTermImageMark alloc] init];
            _doppelganger->_imageCode = _imageCode;
            _doppelganger->_isDoppelganger = YES;
            _doppelganger->_progenitor = self;
        }
        assert(_doppelganger);
        return _doppelganger;
    }
}

- (NSString *)shortDebugDescription {
    return [NSString stringWithFormat:@"[Image %@]", _imageCode];
}

- (id<iTermMark>)progenitor {
    @synchronized ([iTermImageMark class]) {
        return _progenitor;
    }
}

@end
