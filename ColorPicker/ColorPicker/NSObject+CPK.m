#import "NSObject+CPK.h"

@implementation NSObject (CPK)

- (NSImage *)cpk_imageNamed:(NSString *)name {
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:name ofType:@"tiff"];
    return [[NSImage alloc] initWithContentsOfFile:path];
}

@end
