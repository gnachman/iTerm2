//
//  iTermKeyLabels.m
//  iTerm2
//
//  Created by George Nachman on 12/30/16.
//
//

#import "iTermKeyLabels.h"

@implementation iTermKeyLabels

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _map = [(dict[@"map"] ?: @{}) mutableCopy];
        _name = dict[@"name"] ?: @"";
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    return @{ @"map": _map ?: @{},
              @"name": _name ?: @"" };
}

@end
