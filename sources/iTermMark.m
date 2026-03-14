//
//  iTermMark.m
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermMark.h"
#import "CapturedOutput.h"
#import "DebugLogging.h"
#import "NSDictionary+iTerm.h"

static NSString *const kMarkGuidKey = @"Guid";

@implementation iTermMark {
    iTermMark *_doppelganger;
    __weak iTermMark *_progenitor;
    BOOL _isDoppelganger;
    NSString *_guid;
}

@synthesize entry;
@synthesize cachedLocation;

#pragma mark - IntervalTreeObject

- (instancetype)init {
    self = [super init];
    if (self) {
        _guid = [[[NSUUID UUID] UUIDString] copy];
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        NSString *savedGuid = dict[kMarkGuidKey];
        if (savedGuid) {
            _guid = [savedGuid copy];
        } else {
            // Generate new GUID if not present in dictionary (old format or new object)
            _guid = [[[NSUUID UUID] UUIDString] copy];
        }
    }
    return self;
}

- (NSString *)guid {
    return _guid;
}

- (NSString *)stableIdentifier {
    return _guid;
}

- (NSDictionary *)dictionaryValue {
    ITAssertWithMessage(_guid != nil, @"guid should never be nil");
    return @{ kMarkGuidKey: _guid };
}

- (NSDictionary *)dictionaryValueWithTypeInformation {
    return @{ @"class": NSStringFromClass(self.class),
              @"value": [self dictionaryValue] };
}

+ (id<IntervalTreeObject>)intervalTreeObjectWithDictionaryWithTypeInformation:(NSDictionary *)dict {
    NSString *className = dict[@"class"];
    if (!className) {
        return nil;
    }
    NSDictionary *value = dict[@"value"];
    if (!value) {
        return nil;
    }
    Class c = NSClassFromString(className);
    if (!c) {
        return nil;
    }
    if (![c conformsToProtocol:@protocol(IntervalTreeObject)] ||
        ![c instancesRespondToSelector:@selector(initWithDictionary:)]) {
        return nil;
    }
    return [[c alloc] initWithDictionary:value];
}

- (instancetype)copyOfIntervalTreeObject {
    return [[self.class alloc] init];
}

- (BOOL)isDoppelganger {
    @synchronized ([iTermMark class]) {
        return _isDoppelganger;
    }
}

- (id<iTermMark>)doppelganger {
    @synchronized ([iTermMark class]) {
        assert(!_isDoppelganger);
        if (!_doppelganger) {
            _doppelganger = [self copy];
            [_doppelganger becomeDoppelgangerWithProgenitor:self];
        }
        return _doppelganger;
    }
}

- (void)becomeDoppelgangerWithProgenitor:(iTermMark *)progenitor {
    _isDoppelganger = YES;
    _progenitor = progenitor;
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

- (void)copyGuidFrom:(iTermMark *)source {
    _guid = [source->_guid copy];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [[self.class alloc] initWithDictionary:self.dictionaryValue];
}

- (iTermMark *)copy {
    return [self copyWithZone:nil];
}

@end
