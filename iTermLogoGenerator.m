#import "iTermLogoGenerator.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import <QuartzCore/QuartzCore.h>

// key->NSImage

static NSMutableDictionary *gLogoCache;

@implementation iTermLogoGenerator

- (void)dealloc {
  [_textColor release];
  [_backgroundColor release];
  [_tabColor release];
  [_cursorColor release];
  [super dealloc];
}

- (NSString *)keyForColor:(NSColor *)color {
    // Quantizing at 4 bits per component should be enough to produce good logos, while hopefully
    // getting us wins here and there.
    int r = 16 * [color redComponent];
    int g = 16 * [color greenComponent];
    int b = 16 * [color blueComponent];
    return [NSString stringWithFormat:@"%d,%d,%d", r, g, b];
}

- (NSString *)cacheKey {
    return [NSString stringWithFormat:@"%@ %@ %@ %@",
            [self keyForColor:self.textColor],
            [self keyForColor:self.cursorColor],
            [self keyForColor:self.backgroundColor],
            [self keyForColor:self.tabColor]];
}

- (NSImage *)generatedImage {
    NSString *key = [self cacheKey];
    NSImage *cachedImage = gLogoCache[key];
    if (cachedImage) {
        return cachedImage;
    }

    const CGFloat width = 55;
    const CGFloat height = 48;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image lockFocus];

    NSImage *titleBar = [NSImage imageNamed:@"TitleBar.png"];
    [titleBar drawInRect:NSMakeRect(0, 0, width, height)];

    NSImage *tabs = [NSImage imageNamed:@"Tabs.png"];
    [tabs drawInRect:NSMakeRect(0, 0, width, height)];

    if (self.tabColor) {
        [[self.tabColor colorWithAlphaComponent:0.5] set];
        NSRectFillUsingOperation(NSMakeRect(0, 0, width, 4), NSCompositeSourceOver);
        NSRectFillUsingOperation(NSMakeRect(0, height - 4, width, 4), NSCompositeSourceOver);
    }

    [self.backgroundColor set];
    NSRectFill(NSMakeRect(0, 3, 55, 41));

    NSImage *ambientGlare = [NSImage imageNamed:@"Glare.png"];
    [ambientGlare drawInRect:NSMakeRect(0, 0, width, height)];

    NSImage *textLayer = [[NSImage alloc] initWithSize:image.size];
    [textLayer lockFocus];
    NSString *prompt = @"$";
    [prompt drawAtPoint:NSMakePoint(3, 23) withAttributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Myriad Pro" size:16],
                                                             NSForegroundColorAttributeName: self.textColor }];

    [self.cursorColor set];
    NSRectFill(NSMakeRect(15, 26, 6, 14));

    [textLayer unlockFocus];

    if ([self.textColor perceivedBrightness] > [self.backgroundColor perceivedBrightness]) {
        NSImage *blurredText = [textLayer blurredImageWithRadius:5];
        [blurredText drawInRect:NSMakeRect(0, 0, width, height)];
    }
    [textLayer drawInRect:NSMakeRect(0, 0, width, height)];

    NSImage *reflection = [NSImage imageNamed:@"Reflection.png"];
    [reflection drawInRect:NSMakeRect(0, 0, width, height)];
    
    [image unlockFocus];

    if (!gLogoCache) {
        gLogoCache = [[NSMutableDictionary alloc] init];
    }
    gLogoCache[key] = image;

    return image;
}

@end
