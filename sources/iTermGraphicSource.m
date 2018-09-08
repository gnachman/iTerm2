//
//  iTermGraphicSource.m
//  iTerm2
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGraphicSource.h"

#import "iTermProcessCache.h"
#import "iTermTextExtractor.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
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
            
            path = [[NSBundle bundleForClass:[self class]] pathForResource:@"graphic_icons"
                                                                    ofType:@"json"];
            data = [NSData dataWithContentsOfFile:path options:0 error:nil];
            if (data) {
                sGraphicIconMap = [[NSJSONSerialization JSONObjectWithData:data options:0 error:nil] it_invertedGraphicDictionary];
            }
        });
    }
    return self;
}

- (BOOL)updateImageForProcessID:(pid_t)pid enabled:(BOOL)enabled {
    NSImage *image = [self imageForProcessID:pid enabled:enabled];
    if (image == self.image) {
        return NO;
    }
    _image = image;
    return YES;
}

- (NSImage *)imageForProcessID:(pid_t)pid enabled:(BOOL)enabled {
    if (!enabled) {
        return nil;
    }
    NSString *job = [[iTermProcessCache sharedInstance] deepestForegroundJobForPid:pid].name;
    if (!job) {
        return nil;
    }
    
    NSArray *parts = [job componentsInShellCommand];
    NSString *command = parts.firstObject;
    NSString *logicalName = [sGraphicIconMap[command] firstObject];
    if (!logicalName) {
        return nil;
    }
    
    static NSMutableDictionary *images;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        images = [NSMutableDictionary dictionary];
    });
    NSString *iconName = [@"graphic_" stringByAppendingString:logicalName];
    NSImage *image = images[command];
    if (image) {
        return image;
    }
    image = [[NSImage it_imageNamed:iconName forClass:[self class]] it_flippedImage];
    
    NSString *colorCode = sGraphicColorMap[command];
    if (!colorCode) {
        colorCode = sGraphicColorMap[logicalName];
    }
    if (!colorCode) {
        colorCode = @"#888";
    }
    
    NSColor *color = [NSColor colorFromHexString:colorCode];
    image = [image it_imageWithTintColor:color];
    images[command] = image;
    return image;
}

@end
