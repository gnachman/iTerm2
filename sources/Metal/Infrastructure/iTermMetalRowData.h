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

// vector_float4
@property (nonatomic, strong) NSMutableData *backgroundColorData;
@end

