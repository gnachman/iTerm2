#import <Foundation/Foundation.h>

@interface BrokenThing : NSObject
@end

@implementation BrokenThing
- (void)f {
    if (YES) {
}
@end
