#import "LineBufferPosition.h"

@implementation LineBufferPosition {
    long long absolutePosition_;
    int yOffset_;
    BOOL extendsToEndOfLine_;
}

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

- (BOOL)isEqualToLineBufferPosition:(LineBufferPosition *)other {
    if (!other) {
        return NO;
    }
    return (absolutePosition_ == other->absolutePosition_ &&
            yOffset_ == other->yOffset_ &&
            extendsToEndOfLine_ == other->extendsToEndOfLine_);
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

