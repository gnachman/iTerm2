// A framework with a module map, as the prebuilt frameworks the app embeds
// are: Swift imports it as the Clang module Kit, not through the bridging
// header, so its declarations are not in the bridging header's table.
#import <Foundation/Foundation.h>

@interface KitThing : NSObject
- (void)kitMethod;
@end
