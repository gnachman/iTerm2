#import "LineBufferPosition.h"

@implementation LineBufferPosition

@synthesize absolutePosition = absolutePosition_;
@synthesize yOffset = yOffset_;
@synthesize extendsToEndOfLine = extendsToEndOfLine_;

+ (LineBufferPosition *)position {
    return [[[self alloc] init] autorelease];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p abs=%@ yoff=%@ extends=%@>",
            [self class], self,
            @(absolutePosition_), @(yOffset_), @(extendsToEndOfLine_)];
}

- (LineBufferPosition *)predecessor {
    LineBufferPosition *predecessor = [LineBufferPosition position];
    predecessor.absolutePosition = absolutePosition_;
    predecessor.yOffset = yOffset_;
    predecessor.extendsToEndOfLine = extendsToEndOfLine_;
    
    if (extendsToEndOfLine_) {
        predecessor.extendsToEndOfLine = NO;
    } else if (yOffset_ > 0) {
        predecessor.yOffset = yOffset_ - 1;
    } else if (absolutePosition_ > 0) {
        predecessor.absolutePosition = absolutePosition_ - 1;
    }
    
    return predecessor;
}

@end

@implementation LineBufferPositionRange : NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p start=%@ end=%@>", [self class], self, _start, _end];
}

- (void)dealloc {
    [_start release];
    [_end release];
    [super dealloc];
}

@end

