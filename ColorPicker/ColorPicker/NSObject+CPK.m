#import "NSObject+CPK.h"

@implementation NSObject (CPK)

- (NSImage *)cpk_imageNamed:(NSString *)name {
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:name ofType:@"tiff"];
    NSLog(@"Trying to load an image from %@", path);
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    NSLog(@"Image at %@ is %@", path, image);
    return image;
}

@end
