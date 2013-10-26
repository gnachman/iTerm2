//
//  FindContext.m
//  iTerm
//
//  Created by George Nachman on 10/26/13.
//
//

#import "FindContext.h"

@implementation FindContext

@synthesize absBlockNum = absBlockNum_;
@synthesize substring = substring_;
@synthesize options = options_;
@synthesize dir = dir_;
@synthesize offset = offset_;
@synthesize stopAt = stopAt_;
@synthesize status = status_;
@synthesize matchLength = matchLength_;
@synthesize results = results_;
@synthesize hasWrapped = hasWrapped_;

- (void)dealloc {
    [results_ release];
    [substring_ release];
    [super dealloc];
}

- (void)copyFromFindContext:(FindContext *)other {
    self.absBlockNum = other.absBlockNum;
    self.substring = other.substring;
    self.options = other.options;
    self.dir = other.dir;
    self.offset = other.offset;
    self.stopAt = other.stopAt;
    self.status = other.status;
    self.matchLength = other.matchLength;
    self.results = other.results;
    self.hasWrapped = other.hasWrapped;
}

- (void)reset {
    self.substring = nil;
    self.results = nil;
}

@end
