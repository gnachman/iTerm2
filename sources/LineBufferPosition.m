#import "LineBufferPosition.h"

#import "DebugLogging.h"

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

- (NSComparisonResult)compare:(LineBufferPosition *)other {
    NSComparisonResult result = [@(self.absolutePosition) compare:@(other.absolutePosition)];
    if (result != NSOrderedSame) {
        return result;
    }
    result = [@(self.yOffset) compare:@(other.yOffset)];
    if (result != NSOrderedSame) {
        return result;
    }
    if (self.extendsToEndOfLine == other.extendsToEndOfLine) {
        return NSOrderedSame;
    } else if (self.extendsToEndOfLine) {
        return NSOrderedDescending;
    } else {
        return NSOrderedAscending;
    }
}

- (LineBufferPosition *)advancedBy:(int)cells {
    LineBufferPosition *pos = [[[LineBufferPosition alloc] init] autorelease];
    pos.absolutePosition = self.absolutePosition + cells;
    return pos;
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

