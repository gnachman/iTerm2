//
//  VT100WorkingDirectory.m
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import "VT100WorkingDirectory.h"
#import "NSObject+iTerm.h"

static NSString *const kWorkingDirectoryStateWorkingDirectoryKey = @"Working Directory";

@implementation VT100WorkingDirectory {
    VT100WorkingDirectory *_doppelganger;
    __weak VT100WorkingDirectory *_progenitor;
    BOOL _isDoppelganger;
}

@synthesize entry;

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    return [self initWithDirectory:dict[kWorkingDirectoryStateWorkingDirectoryKey]];
}

- (instancetype)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (self) {
        _workingDirectory = [directory copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p workingDirectory=%@ interval=%@ %@>",
            self.class, self, self.workingDirectory, self.entry.interval,
            _isDoppelganger ? @"IsDop" : @"NotDop"];
}

#pragma mark - IntervalTreeObject

- (NSDictionary *)dictionaryValue {
    if (self.workingDirectory) {
        return @{ kWorkingDirectoryStateWorkingDirectoryKey: self.workingDirectory };
    } else {
        return @{};
    }
}

- (NSString *)shortDebugDescription {
    return [NSString stringWithFormat:@"[Dir %@]", self.workingDirectory];
}

- (nonnull id<IntervalTreeObject>)doppelganger {
    @synchronized ([VT100WorkingDirectory class]) {
        assert(!_isDoppelganger);
        if (!_doppelganger) {
            _doppelganger = [self copyOfIntervalTreeObject];
            _doppelganger->_progenitor = self;
            _doppelganger->_isDoppelganger = YES;
        }
        return _doppelganger;
    }
}

- (id<IntervalTreeObject>)progenitor {
    @synchronized ([VT100WorkingDirectory class]) {
        return _progenitor;
    }
}

- (instancetype)copyOfIntervalTreeObject {
    return [[VT100WorkingDirectory alloc] initWithDirectory:self.workingDirectory];
}

@end
