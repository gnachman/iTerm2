
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

@implementation iTermASCIITexture

- (instancetype)initWithAttributes:(iTermASCIITextureAttributes)attributes
                          cellSize:(CGSize)cellSize
                            device:(id<MTLDevice>)device
                          creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull (^)(char, iTermASCIITextureAttributes))creation {
    self = [super init];
    if (self) {
        _parts = (iTermASCIITextureParts *)calloc(128, sizeof(iTermASCIITextureParts));
        _attributes = attributes;
        _textureArray = [[iTermTextureArray alloc] initWithTextureWidth:cellSize.width
                                                          textureHeight:cellSize.height
                                                            arrayLength:iTermASCIITextureCapacity
                                                                 device:device];
        _textureArray.texture.label = [NSString stringWithFormat:@"ASCII texture %@%@%@",
                                       (attributes & iTermASCIITextureAttributesBold) ? @"Bold" : @"",
                                       (attributes & iTermASCIITextureAttributesItalic) ? @"Italic" : @"",
                                       (attributes & iTermASCIITextureAttributesThinStrokes) ? @"ThinStrokes" : @""];

        for (int i = iTermASCIITextureMinimumCharacter; i <= iTermASCIITextureMaximumCharacter; i++) {
            NSDictionary<NSNumber *, iTermCharacterBitmap *> *dict = creation(i, attributes);
            iTermCharacterBitmap *left = dict[@(iTermImagePartFromDeltas(-1, 0))];
            iTermCharacterBitmap *center = dict[@(iTermImagePartFromDeltas(0, 0))];
            iTermCharacterBitmap *right = dict[@(iTermImagePartFromDeltas(1, 0))];
            if (left) {
                _parts[i] |= iTermASCIITexturePartsLeft;
                [_textureArray setSlice:iTermASCIITextureIndexOfCode(i, iTermASCIITextureOffsetLeft)
                              withBitmap:left];
            }
            if (right) {
                _parts[i] |= iTermASCIITexturePartsRight;
                [_textureArray setSlice:iTermASCIITextureIndexOfCode(i, iTermASCIITextureOffsetRight)
                              withBitmap:right];
            }
            if (center) {
                [_textureArray setSlice:iTermASCIITextureIndexOfCode(i, iTermASCIITextureOffsetCenter)
                              withBitmap:center];
            } else {
                ELog(@"Couldn't produce image for ascii %d", i);
            }
        }
    }
    return self;
}

@end

@implementation iTermASCIITextureGroup

- (instancetype)initWithCellSize:(CGSize)cellSize
                          device:(id<MTLDevice>)device
              creationIdentifier:(id)creationIdentifier
                        creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull (^)(char, iTermASCIITextureAttributes))creation {
    self = [super init];
    if (self) {
        _cellSize = cellSize;
        _device = device;
        _creationIdentifier = creationIdentifier;
        _creation = [creation copy];
        CGSize temp = [iTermTextureArray atlasSizeForUnitSize:cellSize
                                                  arrayLength:iTermASCIITextureCapacity
                                                  cellsPerRow:NULL];
        _atlasSize = simd_make_float2(temp.width, temp.height);
    }
    return self;
}

- (iTermASCIITexture *)asciiTextureForAttributes:(iTermASCIITextureAttributes)attributes {
    if (_textures[attributes]) {
        return _textures[attributes];
    }

    _textures[attributes] = [[iTermASCIITexture alloc] initWithAttributes:attributes
                                                                 cellSize:_cellSize
                                                                   device:_device
                                                                 creation:_creation];
    return _textures[attributes];
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

@end

