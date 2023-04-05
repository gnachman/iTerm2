//
//  iTermMark.m
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermMark.h"
#import "CapturedOutput.h"
#import "NSDictionary+iTerm.h"

@implementation iTermMark {
    iTermMark *_doppelganger;
    __weak iTermMark *_progenitor;
}

@synthesize entry;

#pragma mark - IntervalTreeObject

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    return [super init];
}

- (NSDictionary *)dictionaryValue {
    return @{};
}

- (instancetype)copyOfIntervalTreeObject {
    return [[self.class alloc] init];
}

- (id<iTermMark>)doppelganger {
    @synchronized ([iTermMark class]) {
        assert(!_isDoppelganger);
        if (!_doppelganger) {
            _doppelganger = [self copy];
            _doppelganger->_isDoppelganger = YES;
            _doppelganger->_progenitor = self;
        }
        return _doppelganger;
    }
}

- (NSString *)shortDebugDescription {
    return [NSString stringWithFormat:@"[Mark %@]", NSStringFromClass(self.class)];
}

- (id<iTermMark>)progenitor {
    @synchronized ([iTermMark class]) {
        return _progenitor;
    }
}

#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p interval=%@ %@>",
            NSStringFromClass(self.class),
            self,
            self.entry.interval,
            _isDoppelganger ? @"IsDop" : @"NotDop"];
}

#pragma mark - APIs

- (BOOL)isVisible {
    return YES;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [[self.class alloc] initWithDictionary:self.dictionaryValue];
}

- (iTermMark *)copy {
    return [self copyWithZone:nil];
}

@end
