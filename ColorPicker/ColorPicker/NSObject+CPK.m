#import "NSObject+CPK.h"

@implementation NSObject (CPK)

- (NSImage *)cpk_imageNamed:(NSString *)name {
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:name ofType:@"tiff"];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];

    NSString *log = [NSString stringWithFormat:@"Loading %@ (%@). Image is %@\n", path, name, image];
    NSLog(@"%@",log);
    NSString *contents = [NSString stringWithContentsOfFile:@"/tmp/colorlog.txt"] ?: @"";
    contents = [contents stringByAppendingString:log];
    [contents writeToFile:@"/tmp/colorlog.txt" atomically:YES encoding: NSUTF8StringEncoding error:NULL];
    
    return image;
}

@end
