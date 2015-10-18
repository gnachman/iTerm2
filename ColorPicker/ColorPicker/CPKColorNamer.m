#import "CPKColorNamer.h"
#import "CPKKDTree.h"
#import "NSColor+CPK.h"
#import <math.h>

// Picking a color with a different hue will cause silly results. With a multiplier of 1, #fefb67
// gets named "Hit Pink". So we use this to make hues span 0-5 while saturation and brightness each
// take values in 0-1. We will rarely find a nearest neighbor with a significantly different hue.
static const CGFloat kHueMultiplier = 5;

@interface CPKColorNamer ()
@property(nonatomic) CPKKDTree *tree;
@end

@implementation CPKColorNamer

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *filename = [[NSBundle bundleForClass:[self class]] pathForResource:@"colors"
                                                                              ofType:@"txt"];
        NSData *database = [NSData dataWithContentsOfFile:filename];
        NSString *asString = [[NSString alloc] initWithData:database
                                                   encoding:NSUTF8StringEncoding];
        if (!asString) {
            return nil;
        }

        self.tree = [[CPKKDTree alloc] initWithDimensions:3];

        NSArray *rows = [asString componentsSeparatedByString:@"\n"];
        for (NSString *row in rows) {
            if ([row hasPrefix:@"#"]) {
                continue;
            }
            NSArray *parts = [row componentsSeparatedByString:@","];
            if (parts.count == 2) {
                NSString *hex = parts[0];
                NSString *name = parts[1];
                if (hex.length == 6) {
                    NSScanner *scanner = [NSScanner scannerWithString:hex];
                    unsigned int value;
                    if ([scanner scanHexInt:&value]) {
                        int r = (value >> 16) & 0xff;
                        int g = (value >> 8) & 0xff;
                        int b = (value >> 0) & 0xff;

                        NSColor *color = [NSColor cpk_colorWithRed:r / 255.0
                                                             green:g / 255.0
                                                              blue:b / 255.0
                                                             alpha:1];

                        [self.tree addObject:name forKey:@[ @(color.hueComponent * kHueMultiplier),
                                                            @(color.saturationComponent),
                                                            @(color.brightnessComponent)]];
                    }
                }
            }
        }
        [self.tree build];
    }
    return self;
}

- (NSString *)nameForColor:(NSColor *)color {
    NSString *baseName = [self.tree nearestNeighborTo:@[ @(color.hueComponent * kHueMultiplier),
                                                         @(color.saturationComponent),
                                                         @(color.brightnessComponent) ]];
    if (color.alphaComponent < 0.99) {
        return [baseName stringByAppendingFormat:@" (%d%%)",
                   (int)(color.alphaComponent * 100)];
    } else {
        return baseName;
    }
}

@end
