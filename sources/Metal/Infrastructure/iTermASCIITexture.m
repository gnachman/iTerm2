
//
//  iTermASCIITexture.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/2/17.
//

#import "iTermASCIITexture.h"

#import "DebugLogging.h"

const unsigned char iTermASCIITextureMinimumCharacter = 33; // !
const unsigned char iTermASCIITextureMaximumCharacter = 126; // ~

static const NSInteger iTermASCIITextureCapacity = iTermASCIITextureMaximumCharacter - iTermASCIITextureMinimumCharacter + 1;

@implementation iTermASCIITexture

- (instancetype)initWithAttributes:(iTermASCIITextureAttributes)attributes
                          cellSize:(CGSize)cellSize
                            device:(id<MTLDevice>)device
                          creation:(NSImage * _Nonnull (^)(char, iTermASCIITextureAttributes))creation {
    self = [super init];
    if (self) {
        _attributes = attributes;
        _textureArray = [[iTermTextureArray alloc] initWithTextureWidth:cellSize.width
                                                          textureHeight:cellSize.height
                                                            arrayLength:iTermASCIITextureCapacity
                                                                 device:device];
        for (int i = iTermASCIITextureMinimumCharacter; i <= iTermASCIITextureMaximumCharacter; i++) {
            NSImage *image = creation(i, attributes);
            if (image) {
                [_textureArray setSlice:iTermASCIITextureIndexOfCode(i)
                              withImage:creation(i, attributes)];
            } else {
                ELog(@"Couldn't produce image for ascii %d", i);
            }
        }
    }
    return self;
}

@end

@implementation iTermASCIITextureGroup {
    iTermASCIITexture *_textures[iTermASCIITextureAttributesMax * 2];
}

- (instancetype)initWithCellSize:(CGSize)cellSize
                          device:(id<MTLDevice>)device
              creationIdentifier:(id)creationIdentifier
                        creation:(NSImage * _Nonnull (^)(char, iTermASCIITextureAttributes))creation {
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

