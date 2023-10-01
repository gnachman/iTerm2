//
//  iTermGraphicSource.m
//  iTerm2
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGraphicSource.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermProcessCache.h"
#import "iTermTextExtractor.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

static NSDictionary *sGraphicColorMap;
static NSDictionary *sGraphicIconMap;

@interface NSDictionary (Graphic)
- (NSDictionary *)it_invertedGraphicDictionary;
@end

@implementation NSDictionary (Graphic)

- (NSDictionary *)it_invertedGraphicDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [self enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull graphicName, NSArray * _Nonnull obj, BOOL * _Nonnull stop) {
        for (NSString *appName in obj) {
            [dict it_addObject:graphicName toMutableArrayForKey:appName];
        }
    }];
    return dict;
}

@end

@implementation iTermGraphicSource

- (instancetype)init {
    self = [super init];
    if (self) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"graphic_colors"
                                                                              ofType:@"json"];
            NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
            if (data) {
                sGraphicColorMap = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            }

            NSString *const appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
            path = [appSupport stringByAppendingPathComponent:@"graphic_colors.json"];
            data = [NSData dataWithContentsOfFile:path options:0 error:nil];
            if (data) {
                NSDictionary *dict = [NSDictionary castFrom:[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]];
                sGraphicColorMap = [sGraphicColorMap dictionaryByMergingDictionary:dict];
            }

            path = [[NSBundle bundleForClass:[self class]] pathForResource:@"graphic_icons"
                                                                    ofType:@"json"];
            data = [NSData dataWithContentsOfFile:path options:0 error:nil];
            if (data) {
                sGraphicIconMap = [[NSJSONSerialization JSONObjectWithData:data options:0 error:nil] it_invertedGraphicDictionary];
            }
            path = [appSupport stringByAppendingPathComponent:@"graphic_icons.json"];
            data = [NSData dataWithContentsOfFile:path options:0 error:nil];
            if (data) {
                NSDictionary *dict = [[NSDictionary castFrom:[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]] it_invertedGraphicDictionary];
                sGraphicIconMap = [sGraphicIconMap dictionaryByMergingDictionary:dict];
            }
        });
    }
    return self;
}

- (BOOL)updateImageForProcessID:(pid_t)pid
                        enabled:(BOOL)enabled
            processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider {
    NSImage *image = [self imageForProcessID:pid enabled:enabled processInfoProvider:processInfoProvider];
    if (image == self.image) {
        return NO;
    }
    _image = image;
    return YES;
}

- (BOOL)updateImageForJobName:(NSString *)name enabled:(BOOL)enabled {
    NSImage *image = [self imageForJobName:name enabled:enabled];
    if (image == self.image) {
        return NO;
    }
    _image = image;
    return YES;
}

- (NSImage *)imageForProcessID:(pid_t)pid
                       enabled:(BOOL)enabled
           processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider {
    if (!enabled) {
        return nil;
    }
    NSString *job = [processInfoProvider deepestForegroundJobForPid:pid].name;
    if (!job) {
        return nil;
    }
    
    NSArray *parts = [job componentsInShellCommand];
    NSString *command = parts.firstObject;

    return [self imageForJobName:command enabled:YES];
}

- (NSString *)normalizedCommand:(NSString *)nonnormalCommand {
    // A little hack for emacs. So far I haven't found anything else that needs normalization.
    if ([nonnormalCommand hasPrefix:@"Emacs-"] || [nonnormalCommand hasPrefix:@"emacs-"]) {
        return @"emacs";
    }
    if ([nonnormalCommand hasPrefix:@"Python"] || [nonnormalCommand hasPrefix:@"python"]) {
        NSString *suffix = [nonnormalCommand substringFromIndex:[@"python" length]];
        if ([suffix rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location == NSNotFound) {
            // python followed by non-letters, e.g. python3.7
            return @"python";
        }
    }
    return nonnormalCommand;
}

static NSMutableDictionary *CachedGraphicImages(void) {
    static NSMutableDictionary *images;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        images = [NSMutableDictionary dictionary];
    });
    return images;
}

- (NSImage *)imageForJobName:(NSString *)command enabled:(BOOL)enabled {
    if (!enabled || !command) {
        return nil;
    }
    NSImage *image = [self imageForJobName:command] ?: [self defaultImageForCommand:command];
    CachedGraphicImages()[command] = image;
    return image;
}

- (NSImage *)imageForJobName:(NSString *)jobName {
    NSString *command = [self normalizedCommand:jobName];
    NSString *logicalName = [sGraphicIconMap[command] firstObject];
    if (!logicalName) {
        return nil;
    }
    
    NSString *iconName = [@"graphic_" stringByAppendingString:logicalName];
    NSImage *image = CachedGraphicImages()[command];
    if (image) {
        return image;
    }
    image = [NSImage it_imageNamed:iconName forClass:[self class]];
    if (!image) {
        NSString *const appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
        NSString *path = [appSupport stringByAppendingPathComponent:[iconName stringByAppendingPathExtension:@"png"]];
        image = [NSImage it_imageWithScaledBitmapFromFile:path pointSize:NSMakeSize(16, 16)];
    }
    NSString *colorCode = sGraphicColorMap[command];
    if (!colorCode) {
        colorCode = sGraphicColorMap[logicalName];
    }
    if (!colorCode) {
        colorCode = @"#888";
    }
    image = [self image:image tinted:colorCode];
    return image;
}

- (NSImage *)image:(NSImage *)image tinted:(NSString *)colorCode {
    if (self.disableTinting) {
        return image;
    }

    NSColor *color = [NSColor colorFromHexString:colorCode];
    image = [image it_imageWithTintColor:color];
    return image;
}

- (NSImage *)defaultImageForCommand:(NSString *)jobName {
    if (![iTermAdvancedSettingsModel defaultIconsUsingLetters]) {
        return nil;
    }
    NSString *command = [self normalizedCommand:jobName];
    if (command.length == 0) {
        return nil;
    }
    NSString *firstLetter = [jobName firstComposedCharacter:nil];
    NSImage *image = [self imageForLetter:firstLetter];
    return [self image:image tinted:[self randomTintColorForString:jobName]];
}

- (NSImage *)imageForLetter:(NSString *)letter {
    const NSSize size = NSMakeSize(16, 16);
    return [NSImage imageOfSize:size drawBlock:^{
        // Set up the font and style
        NSFont *font = [NSFont boldSystemFontOfSize:12];
        NSDictionary *attributes = @{NSFontAttributeName: font,
                                     NSForegroundColorAttributeName: [NSColor blackColor] };

        // Create attributed string
        NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:[letter uppercaseString]
                                                                      attributes:attributes];

        // Calculate size and origin to center the text
        NSSize textSize = [attrStr size];
        NSPoint textOrigin = NSMakePoint((size.width - textSize.width) / 2.0,
                                        (size.height - textSize.height) / 2.0);

        // Draw the filled circle
        NSBezierPath *circlePath = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1,
                                                                                     1,
                                                                                     size.width - 2,
                                                                                     size.height - 2)];
        [[NSColor blackColor] setFill];
        [circlePath fill];

        // Set the blending mode to subtract the letter from the circle
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext.currentContext setCompositingOperation:NSCompositingOperationDestinationOut];

        // Draw the attributed string at the calculated origin point
        [attrStr drawAtPoint:textOrigin];

        [NSGraphicsContext restoreGraphicsState];
    }];
}

- (iTermSRGBColor)colorForString:(NSString *)string {
    NSUInteger hash = [string hashWithDJB2];
    int red = hash & 255;
    int green = (hash >> 8) & 255;
    int blue = (hash >> 16) & 255;

    return (iTermSRGBColor){ red / 255.0, green / 255.0, blue / 255.0 };
}

- (NSString *)randomTintColorForString:(NSString *)string {
    NSMutableString *acc = [string mutableCopy];
    const CGFloat minBrightness = 0.30;
    const CGFloat maxBrightness = 0.50;
    iTermSRGBColor color = [self colorForString:acc];
    CGFloat brightness = iTermPerceptualBrightnessSRGB(color);
    while (brightness < minBrightness || brightness > maxBrightness) {
        [acc appendFormat:@"%0.2f%0.2f%0.2f", color.r, color.g, color.b];
        color = [self colorForString:acc];;
        brightness = iTermPerceptualBrightnessSRGB(color);
    }
    return [NSString stringWithFormat:@"#%02x%02x%02x",
            (int)(color.r * 255), (int)(color.g * 255), (int)(color.b * 255)];
}

@end
