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
}

@synthesize entry;

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        self.workingDirectory = dict[kWorkingDirectoryStateWorkingDirectoryKey];
    }
    return self;
}

- (void)dealloc {
    [_workingDirectory release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p workingDirectory=%@ interval=%@>",
            self.class, self, self.workingDirectory, self.entry.interval];
}

#pragma mark - IntervalTreeObject

- (NSDictionary *)dictionaryValue {
    if (self.workingDirectory) {
        return @{ kWorkingDirectoryStateWorkingDirectoryKey: self.workingDirectory };
    } else {
        return @{};
    }
}

- (nonnull id<IntervalTreeObject>)doppelganger {
    @synchronized ([VT100WorkingDirectory class]) {
        if (!_doppelganger) {
            _doppelganger = [self copyOfIntervalTreeObject];
            _doppelganger->_progenitor = self;
        }
        return _doppelganger;
    }
}

- (instancetype)copyOfIntervalTreeObject {
    VT100WorkingDirectory *copy = [[VT100WorkingDirectory alloc] init];
    copy.workingDirectory = self.workingDirectory;
    return copy;
}

@end
