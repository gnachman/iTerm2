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

    const CGFloat width = 48;
    const CGFloat height = 48;
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(width, height)] autorelease];
    [image lockFocus];

    NSImage *frame = [NSImage imageNamed:@"LogoFrame.png"];
    NSImage *shadow = [NSImage imageNamed:@"LogoShadow.png"];

    [_backgroundColor set];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path appendBezierPathWithRoundedRect:NSMakeRect(3, 6, 42, 36) xRadius:2 yRadius:2];
    [path fill];

    [frame drawInRect:NSMakeRect(0, 0, width, height)];
    if (self.tabColor) {
        [[self.tabColor colorWithAlphaComponent:0.5] set];
        CGFloat tabHeight = 9;
        NSRectFillUsingOperation(NSMakeRect(0, height - tabHeight, width, tabHeight), NSCompositingOperationSourceIn);
    }

    [shadow drawInRect:NSMakeRect(0, 0, width, height)];
    NSString *prompt = @"$";
    [prompt drawAtPoint:NSMakePoint(7, 25) withAttributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica Neue" size:12],
                                                             NSForegroundColorAttributeName: self.textColor }];

    [self.cursorColor set];
    NSRectFill(NSMakeRect(15.5, 27, 5.5, 11));

    [image unlockFocus];

    if (!gLogoCache) {
        gLogoCache = [[NSMutableDictionary alloc] init];
    }
    gLogoCache[key] = image;

    return image;
}

@end
