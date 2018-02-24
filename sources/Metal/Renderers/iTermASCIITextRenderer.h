//
//  iTermASCIITextRenderer.h
//  iTerm2Shared
//
//  Created by George Nachman on 2/17/18.
//

#import <Foundation/Foundation.h>
#import "iTermASCIITexture.h"
#import "iTermMetalCellRenderer.h"
#import "iTermTextRendererCommon.h"

@class iTermCharacterBitmap;
@class iTermData;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermASCIIRow : NSObject
@property (nonatomic, strong) iTermData *screenChars;
@property (nonatomic, strong) NSIndexSet *selectedIndices;
@property (nonatomic, strong) NSData *findMatches;
@property (nonatomic) NSRange markedRange;
@property (nonatomic) NSRange underlinedRange;
@property (nonatomic, strong) NSIndexSet *annotatedIndices;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermASCIITextRendererTransientState : iTermMetalCellRendererTransientState

@property (nonatomic) iTermMetalUnderlineDescriptor underlineDescriptor;
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;
@property (nonatomic) VT100GridCoord debugCoord;

// screen_char_t array
- (void)addRow:(iTermASCIIRow *)row;

@end

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermASCIITextRenderer : NSObject<iTermMetalCellRenderer>

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setASCIICellSize:(CGSize)cellSize
      creationIdentifier:(id)creationIdentifier
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation;

@end

NS_ASSUME_NONNULL_END

