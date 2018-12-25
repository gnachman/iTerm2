//
//  iTermBacktraceFrame.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/24/18.
//

#import "iTermBacktraceFrame.h"

@implementation iTermBacktraceFrame

- (instancetype)initWithString:(NSString *)string {
    self = [super init];
    if (self) {
        _stringValue = [string copy];
    }
    return self;
}

@end
