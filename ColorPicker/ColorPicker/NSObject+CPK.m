#import "NSObject+CPK.h"

@implementation NSObject (CPK)

- (NSImage *)cpk_imageNamed:(NSString *)name {
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:name ofType:@"tiff"];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    NSString *mainBundle = [[[NSBundle mainBundle] bundleURL] path];
    NSString *suffix = @"Contents/Frameworks/ColorPicker.framework/Resources";
    NSURL *url = [NSURL fileURLWithPath:[[[mainBundle stringByAppendingPathComponent:suffix] stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"tiff"]];

    if (!image) {
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        image = [bundle imageForResource:name];

        if (!image) {
            image = [[NSImage alloc] initWithContentsOfURL:url];
        }
    }

    NSString *log = [NSString stringWithFormat:@"Loading %@ (%@). Image is %@. Bundle for %@ is %@. Main bundle is %@. Constructed url is %@\n", path, name, image, [self class],
                     [NSBundle bundleForClass:[self class]], [NSBundle mainBundle], url];
    NSLog(@"%@",log);

    NSMutableString *contents = [([NSString stringWithContentsOfFile:@"/tmp/colorlog.txt"] ?: @"") mutableCopy];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [contents appendFormat:@"BEGIN LIST OF BUNDLES\n"];
        for (NSBundle *bundle in [NSBundle allBundles]) {
            [contents appendFormat:@"%@\n", bundle];
        }
        [contents appendFormat:@"END LIST OF BUNDLES\n\n"];
    });

    [contents appendString:log];
    [contents writeToFile:@"/tmp/colorlog.txt" atomically:YES encoding: NSUTF8StringEncoding error:NULL];

    return image;
}

@end
