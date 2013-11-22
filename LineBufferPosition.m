#import "LineBufferPosition.h"

@implementation LineBufferPosition

@synthesize absolutePosition = absolutePosition_;
@synthesize yOffset = yOffset_;
@synthesize extendsToEndOfLine = extendsToEndOfLine_;

+ (LineBufferPosition *)position {
    return [[[self alloc] init] autorelease];
}

@end
