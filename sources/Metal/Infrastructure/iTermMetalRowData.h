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
@class iTermBidiDisplayInfo;
@class iTermKittyImageRun;
@class iTermMetalImageRun;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalRowData : NSObject
@property (nonatomic) int y;  // 0 = top of screen
@property (nonatomic) long long absLine;

// iTermMetalGlyphKey
@property (nonatomic, strong) iTermGlyphKeyData *keysData;
@property (nonatomic) NSUInteger glyphKeyCount;

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
@property (nonatomic) BOOL hoverState;  // Is the mouse over a row that has a block?
@property (nonatomic) BOOL lineStyleMark;
@property (nonatomic) int lineStyleMarkRightInset;

// Last-changed timestamp, if used.
@property (nonatomic, strong) NSDate *date;

@property (nonatomic, readonly) NSMutableArray<iTermMetalImageRun *> *imageRuns;
@property (nonatomic) BOOL belongsToBlock;
@property (nonatomic, readonly) NSMutableArray<iTermKittyImageRun *> *kittyImageRuns;

@property (nonatomic, readonly) BOOL hasFold;

- (void)writeDebugInfoToFolder:(NSURL *)folder;

@end
