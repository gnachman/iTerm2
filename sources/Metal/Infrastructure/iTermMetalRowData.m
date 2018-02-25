//
//  iTermMetalRowData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import "iTermMetalRowData.h"

#import "iTermMetalGlyphKey.h"
#import "iTermTextRendererCommon.h"

@implementation iTermMetalRowData

- (instancetype)init {
    self = [super init];
    if (self) {
        _imageRuns = [NSMutableArray array];
    }
    return self;
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    NSString *info = [NSString stringWithFormat:
                      @"y=%@\n"
                      @"numberOfDrawableGlyphs=%@\n"
                      @"markStyle=%@\n"
                      @"date=%@\n",
                      @(self.y),
                      @(self.numberOfDrawableGlyphs),
                      @(self.markStyle),
                      self.date];
    [info writeToURL:[folder URLByAppendingPathComponent:@"info.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];

    @autoreleasepool {
        NSMutableString *glyphKeysString = [NSMutableString string];
        iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)_keysData.mutableBytes;
        for (int i = 0; i < _keysData.length / sizeof(iTermMetalGlyphKey); i++) {
            NSString *glyphKey = iTermMetalGlyphKeyDescription(&glyphKeys[i]);
            [glyphKeysString appendFormat:@"%4d: %@\n", i, glyphKey];
        }
        [glyphKeysString writeToURL:[folder URLByAppendingPathComponent:@"GlyphKeys.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    }
}

@end

