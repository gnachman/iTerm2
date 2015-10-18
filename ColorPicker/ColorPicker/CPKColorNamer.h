#import <Cocoa/Cocoa.h>

@interface CPKColorNamer : NSObject

+ (instancetype)sharedInstance;
- (NSString *)nameForColor:(NSColor *)color;

@end
