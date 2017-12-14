//
//  iTermMetalRowData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import <Foundation/Foundation.h>


@interface iTermMetalRowData : NSObject
@property (nonatomic) int y;

// iTermMetalGlyphKey
@property (nonatomic, strong) NSMutableData *keysData;

// iTermMetalGlyphAttributes
@property (nonatomic, strong) NSMutableData *attributesData;

// iTermMetalBackgroundColorRLE
@property (nonatomic, strong) NSMutableData *backgroundColorRLEData;

@property (nonatomic) int numberOfBackgroundRLEs;

// Number of elements in preceding arrays to use.
@property (nonatomic) int numberOfDrawableGlyphs;

@end

