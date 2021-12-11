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

@implementation iTermMark

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

#pragma mark - NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p interval=%@>",
            self.class, self, self.entry.interval];
}

#pragma mark - APIs

- (BOOL)isVisible {
    return YES;
}

@end
