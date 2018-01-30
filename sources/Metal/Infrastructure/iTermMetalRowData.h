//
//  iTermMetalRowData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import <Foundation/Foundation.h>

#import "iTermMarkRenderer.h"

@class iTermMetalImageRun;

// I used to use NSMutableData but for some reason I couldn't find they never
// got dealloced. Changing it to be my own type somehow fixed it. It might've
// been some kind of funny optimization in the SDK that went wrong is my only
// guess. Activity monitor showed unbounded growth so I'd rather have this
// gross hack than such a leak.
@interface iTermData : NSObject
@property (nonatomic, readonly) void *mutableBytes;
@property (nonatomic) NSUInteger length;

+ (instancetype)dataOfLength:(NSUInteger)length;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermMetalRowData : NSObject
@property (nonatomic) int y;

// iTermMetalGlyphKey
@property (nonatomic, strong) iTermData *keysData;

// iTermMetalGlyphAttributes
@property (nonatomic, strong) iTermData *attributesData;

// iTermMetalBackgroundColorRLE
@property (nonatomic, strong) iTermData *backgroundColorRLEData;

@property (nonatomic) int numberOfBackgroundRLEs;

// Number of elements in preceding arrays to use.
@property (nonatomic) int numberOfDrawableGlyphs;

@property (nonatomic) iTermMarkStyle markStyle;

// Last-changed timestamp, if used.
@property (nonatomic, strong) NSDate *date;

@property (nonatomic, readonly) NSMutableArray<iTermMetalImageRun *> *imageRuns;

- (void)writeDebugInfoToFolder:(NSURL *)folder;

@end
