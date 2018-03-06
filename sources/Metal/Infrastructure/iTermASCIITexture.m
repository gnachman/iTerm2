
//
//  iTermASCIITexture.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/2/17.
//

#import "iTermASCIITexture.h"

#import "DebugLogging.h"

const unsigned char iTermASCIITextureMinimumCharacter = 32; // space
const unsigned char iTermASCIITextureMaximumCharacter = 126; // ~

static const NSInteger iTermASCIITextureCapacity = iTermASCIITextureOffsetCount * (iTermASCIITextureMaximumCharacter - iTermASCIITextureMinimumCharacter + 1);
static const int iTermASCIITextureNumberOfStyles = iTermASCIITextureAttributesMax * 2;

@implementation iTermASCIITexture

- (instancetype)initWithAttributes:(iTermASCIITextureAttributes)attributes
                          cellSize:(CGSize)cellSize
                            device:(id<MTLDevice>)device
                      textureArray:(iTermTextureArray *)textureArray
                     startingIndex:(int)startingIndex
                          creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull (^)(char, iTermASCIITextureAttributes))creation {
    self = [super init];
    if (self) {
        _parts = (iTermASCIITextureParts *)calloc(128, sizeof(iTermASCIITextureParts));
        _attributes = attributes;
        NSLog(@"base=%@", @(startingIndex));
        for (int i = iTermASCIITextureMinimumCharacter; i <= iTermASCIITextureMaximumCharacter; i++) {
            NSLog(@"char=%@ (%c)", @(i), (char)i);

            NSDictionary<NSNumber *, iTermCharacterBitmap *> *dict = creation(i, attributes);
            iTermCharacterBitmap *left = dict[@(iTermImagePartFromDeltas(-1, 0))];
            iTermCharacterBitmap *center = dict[@(iTermImagePartFromDeltas(0, 0))];
            iTermCharacterBitmap *right = dict[@(iTermImagePartFromDeltas(1, 0))];
            if (left) {
                _parts[i] |= iTermASCIITexturePartsLeft;
                [textureArray setSlice:iTermASCIITextureIndexOfCode(startingIndex, i,  iTermASCIITextureOffsetLeft)
                            withBitmap:left];
            } else {
                [textureArray clearSlice:iTermASCIITextureIndexOfCode(startingIndex, i, iTermASCIITextureOffsetLeft)];
            }
            if (right) {
                _parts[i] |= iTermASCIITexturePartsRight;
                [textureArray setSlice:iTermASCIITextureIndexOfCode(startingIndex, i, iTermASCIITextureOffsetRight)
                            withBitmap:right];
            } else {
                [textureArray clearSlice:iTermASCIITextureIndexOfCode(startingIndex, i, iTermASCIITextureOffsetRight)];
            }
            if (center) {
                [textureArray setSlice:iTermASCIITextureIndexOfCode(startingIndex, i, iTermASCIITextureOffsetCenter)
                            withBitmap:center];
                NSLog(@"%@> %c at %@", @(startingIndex), (char)i, @(iTermASCIITextureIndexOfCode(startingIndex, i, iTermASCIITextureOffsetCenter)));
            } else {
                [textureArray clearSlice:iTermASCIITextureIndexOfCode(startingIndex, i, iTermASCIITextureOffsetCenter)];
                ELog(@"Couldn't produce image for ascii %d", i);
            }
        }
    }
    return self;
}

- (void)dealloc {
    free(_parts);
}

@end

@implementation iTermASCIITextureGroup {
    NSMutableArray<iTermASCIITexture *> *_asciiTextures;
}

- (instancetype)initWithCellSize:(CGSize)cellSize
                          device:(id<MTLDevice>)device
              creationIdentifier:(id)creationIdentifier
                        creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull (^)(char, iTermASCIITextureAttributes))creation {
    self = [super init];
    if (self) {
        _cellSize = cellSize;
        CGSize temp = [iTermTextureArray atlasSizeForUnitSize:_cellSize
                                                  arrayLength:iTermASCIITextureCapacity * iTermASCIITextureNumberOfStyles
                                                  cellsPerRow:NULL];
        _atlasSize = simd_make_float2(temp.width, temp.height);
        _asciiTextures = [NSMutableArray array];

        _device = device;
        _creationIdentifier = creationIdentifier;
        _creation = [creation copy];
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[iTermASCIITextureGroup class]]) {
        return NO;
    }
    iTermASCIITextureGroup *other = object;
    return (CGSizeEqualToSize(other.cellSize, _cellSize) &&
            other.device == _device &&
            [other.creationIdentifier isEqual:_creationIdentifier]);
}

- (void)renderGlyphsToTexture {
    _compositeTextureArray = [[iTermTextureArray alloc] initWithTextureWidth:_cellSize.width
                                                               textureHeight:_cellSize.height
                                                                 arrayLength:iTermASCIITextureCapacity * iTermASCIITextureNumberOfStyles
                                                                      device:_device];
    _compositeTextureArray.texture.label = [NSString stringWithFormat:@"Composite ASCII Texture"];
    [_compositeTextureArray fillWhite];
    for (int i = 0; i < iTermASCIITextureAttributesMax * 2; i++) {
        iTermASCIITexture *asciiTexture = [[iTermASCIITexture alloc] initWithAttributes:i
                                                                               cellSize:_cellSize
                                                                                 device:_device
                                                                           textureArray:_compositeTextureArray
                                                                          startingIndex:i * iTermASCIITextureGlyphsPerStyle * 3
                                                                               creation:_creation];
        [_asciiTextures addObject:asciiTexture];

    }
}

@end

