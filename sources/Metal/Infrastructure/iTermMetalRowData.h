//
//  iTermMetalRowData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import <Foundation/Foundation.h>

#import "iTermData.h"
#import "iTermMarkRenderer.h"

@class ScreenCharArray;
@class iTermMetalImageRun;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalRowData : NSObject
@property (nonatomic) int y;  // 0 = top of screen
@property (nonatomic) int line;  // 0 = top of history

// iTermMetalGlyphKey
@property (nonatomic, strong) iTermGlyphKeyData *keysData;

// iTermMetalGlyphAttributes
@property (nonatomic, strong) iTermAttributesData *attributesData;

// iTermMetalBackgroundColorRLE
@property (nonatomic, strong) iTermData *backgroundColorRLEData;

// screen_char_t
@property (nonatomic, strong) ScreenCharArray *screenCharArray;

@property (nonatomic) int numberOfBackgroundRLEs;

// Number of elements in preceding arrays to use.
@property (nonatomic) int numberOfDrawableGlyphs;

@property (nonatomic) iTermMarkStyle markStyle;
@property (nonatomic) BOOL lineStyleMark;
@property (nonatomic) int lineStyleMarkRightInset;

// Last-changed timestamp, if used.
@property (nonatomic, strong) NSDate *date;

@property (nonatomic, readonly) NSMutableArray<iTermMetalImageRun *> *imageRuns;
@property (nonatomic) BOOL belongsToBlock;

- (void)writeDebugInfoToFolder:(NSURL *)folder;

@end
