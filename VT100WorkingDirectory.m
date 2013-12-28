//
//  VT100WorkingDirectory.m
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import "VT100WorkingDirectory.h"

@implementation VT100WorkingDirectory
@synthesize entry;

- (void)dealloc {
    [_workingDirectory release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p workingDirectory=%@ interval=%@>",
            self.class, self, self.workingDirectory, self.entry.interval];
}

@end
