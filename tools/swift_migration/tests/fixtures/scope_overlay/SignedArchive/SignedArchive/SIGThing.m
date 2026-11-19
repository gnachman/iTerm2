#import "SIGThing.h"

@implementation SIGThing

- (NSData *)archive {
    return [NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:YES error:nil];
}

@end
