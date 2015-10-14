//
//  FindContext.m
//  iTerm
//
//  Created by George Nachman on 10/26/13.
//
//

#import "FindContext.h"

// Default max time per iteration of search.
static const NSTimeInterval kDefaultMaxTime = 0.1;

@implementation FindContext {
    int absBlockNum_;
    NSString* substring_;
    FindOptions options_;
    int dir_;
    int offset_;
    int stopAt_;
    FindContextStatus status_;
    int matchLength_;
    NSMutableArray* results_;
    BOOL hasWrapped_;
    NSTimeInterval maxTime_;
}

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
@synthesize maxTime = maxTime_;

- (instancetype)init {
    self = [super init];
    if (self) {
        maxTime_ = kDefaultMaxTime;
    }
    return self;
}

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
    self.maxTime = other.maxTime;
}

- (void)reset {
    self.substring = nil;
    self.results = nil;
}

- (void)setSubstring:(NSString *)substring {
    [substring_ autorelease];
    substring_ = [substring copy];
}

@end
