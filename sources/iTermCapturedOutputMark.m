//
//  iTermCapturedOutputMark.m
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermCapturedOutputMark.h"
#import "NSStringITerm.h"

static NSString *const kMarkGuidKey = @"Guid";

@implementation iTermCapturedOutputMark

@synthesize guid = _guid;
#warning TODO: I hae no idea why the compiler insists on these @dynamics. Make sure it works.
@dynamic interval;
@dynamic object;

- (NSString *)guid {
    if (!_guid) {
        self.guid = [NSString uuid];
    }
    return _guid;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super initWithDictionary:dict];
    if (self) {
        _guid = [dict[kMarkGuidKey] copy];
    }
    return self;
}

- (BOOL)isVisible {
    return NO;
}

- (NSDictionary *)dictionaryValue {
    NSMutableDictionary *dict = [[super dictionaryValue] mutableCopy];
    dict[kMarkGuidKey] = self.guid;
    return dict;
}

@end
