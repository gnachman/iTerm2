//
//  iTermMetalRowData.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import "iTermMetalRowData.h"

#import "iTermMetalGlyphKey.h"
#import "iTermTextRendererCommon.h"
#import "ScreenChar.h"

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
                      @"numberOfBackgroundRLEs=%@\n"
                      @"numberOfDrawableGlyphs=%@\n"
                      @"markStyle=%@\n"
                      @"date=%@\n",
                      @(self.y),
                      @(self.numberOfBackgroundRLEs),
                      @(self.numberOfDrawableGlyphs),
                      @(self.markStyle),
                      self.date];
    [info writeToURL:[folder URLByAppendingPathComponent:@"info.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];

    @autoreleasepool {
        NSMutableString *glyphKeysString = [NSMutableString string];
        const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)_keysData.bytes;
        for (int i = 0; i < _keysData.length / sizeof(iTermMetalGlyphKey); i++) {
            NSString *glyphKey = iTermMetalGlyphKeyDescription(&glyphKeys[i]);
            [glyphKeysString appendFormat:@"%4d: %@\n", i, glyphKey];
        }
        [glyphKeysString writeToURL:[folder URLByAppendingPathComponent:@"GlyphKeys.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    }

    @autoreleasepool {
        NSMutableString *attributesString = [NSMutableString string];
        iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)_attributesData.mutableBytes;
        for (int i = 0; i < _attributesData.length / sizeof(iTermMetalGlyphAttributes); i++) {
            NSString *attribute = iTermMetalGlyphAttributesDescription(&attributes[i]);
            [attributesString appendFormat:@"%4d: %@\n", i, attribute];
        }
        [attributesString writeToURL:[folder URLByAppendingPathComponent:@"Attributes.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    }

    @autoreleasepool {
        NSMutableString *bgColorsString = [NSMutableString string];
        iTermMetalBackgroundColorRLE *bg = (iTermMetalBackgroundColorRLE *)_backgroundColorRLEData.mutableBytes;
        for (int i = 0; i < _numberOfBackgroundRLEs; i++) {
            [bgColorsString appendFormat:@"%@\n", iTermMetalBackgroundColorRLEDescription(&bg[i])];
        }
        [bgColorsString writeToURL:[folder URLByAppendingPathComponent:@"BackgroundColors.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    }

    @autoreleasepool {
        NSMutableString *lineString = [NSMutableString string];
        const screen_char_t *const line = (screen_char_t *)_lineData.mutableBytes;
        for (int i = 0; i < _lineData.length / sizeof(screen_char_t); i++) {
            screen_char_t c = line[i];
            [lineString appendFormat:@"%4d: %@\n", i, [self formatChar:c]];
        }
        [lineString writeToURL:[folder URLByAppendingPathComponent:@"ScreenChars.txt"]
                    atomically:NO
                      encoding:NSUTF8StringEncoding
                         error:NULL];
    }
}

- (NSString *)formatChar:(screen_char_t)c {
    return [NSString stringWithFormat:@"code=%x (%@) foregroundColor=%@ fgGreen=%@ fgBlue=%@ backgroundColor=%@ bgGreen=%@ bgBlue=%@ foregroundColorMode=%@ backgroundColorMode=%@ complexChar=%@ bold=%@ faint=%@ italic=%@ blink=%@ underline=%@ image=%@ unused=%@ urlCode=%@",
            (int)c.code,
            ScreenCharToStr(&c),
            @(c.foregroundColor),
            @(c.fgGreen),
            @(c.fgBlue),
            @(c.backgroundColor),
            @(c.bgGreen),
            @(c.bgBlue),
            @(c.foregroundColorMode),
            @(c.backgroundColorMode),
            @(c.complexChar),
            @(c.bold),
            @(c.faint),
            @(c.italic),
            @(c.blink),
            @(c.underline),
            @(c.image),
            @(c.unused),
            @(c.urlCode)];
}

@end

