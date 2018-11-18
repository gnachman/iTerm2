
//
//  iTermASCIITexture.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/2/17.
//

#import "iTermASCIITexture.h"

#import "DebugLogging.h"
#import "iTermCharacterSource.h"

const unsigned char iTermASCIITextureMinimumCharacter = 32; // space
const unsigned char iTermASCIITextureMaximumCharacter = 126; // ~

static const NSInteger iTermASCIITextureCapacity = iTermASCIITextureOffsetCount * (iTermASCIITextureMaximumCharacter - iTermASCIITextureMinimumCharacter + 1);

@interface iTermASCIITextureCache : NSObject<NSCacheDelegate>

+ (instancetype)sharedInstance;
- (iTermASCIITexture *)asciiTextureWithAttributes:(iTermASCIITextureAttributes)attributes
                                       descriptor:(iTermCharacterSourceDescriptor *)descriptor
                                           device:(id<MTLDevice>)device
                                         creation:(iTermASCIITexture * (^)(void))creation;
- (void)addAsciiTexture:(iTermASCIITexture *)texture
         withAttributes:(iTermASCIITextureAttributes)attributes
             descriptor:(iTermCharacterSourceDescriptor *)descriptor
                 device:(id<MTLDevice>)device;

@end

@implementation iTermASCIITextureCache {
    NSCache *_sharedCache;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermASCIITextureCache alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sharedCache = [[NSCache alloc] init];
        _sharedCache.countLimit = 256;
        _sharedCache.delegate = self;
    }
    return self;
}

- (iTermASCIITexture *)asciiTextureWithAttributes:(iTermASCIITextureAttributes)attributes
                                       descriptor:(iTermCharacterSourceDescriptor *)descriptor
                                           device:(id<MTLDevice>)device
                                         creation:(iTermASCIITexture *(^)(void))creation {
    id key = [self keyForAttributes:attributes descriptor:descriptor device:device];
    iTermASCIITexture *texture;
    @synchronized(_sharedCache) {
        texture = [_sharedCache objectForKey:key];
        if (!texture) {
            texture = creation();
            [self addAsciiTexture:texture withAttributes:attributes descriptor:descriptor device:device];
        }
    }
    DLog(@"Texture for %@ is %@", key, texture);
    return texture;
}

// NOTE: Only call this in @synchronized(_sharedCache)
- (void)addAsciiTexture:(iTermASCIITexture *)texture
         withAttributes:(iTermASCIITextureAttributes)attributes
             descriptor:(iTermCharacterSourceDescriptor *)descriptor
                 device:(id<MTLDevice>)device {
    id key = [self keyForAttributes:attributes descriptor:descriptor device:device];
    DLog(@"Add texture %@ for key %@", texture, key);
    [_sharedCache setObject:texture forKey:key];
}

- (id)keyForAttributes:(iTermASCIITextureAttributes)attributes
            descriptor:(iTermCharacterSourceDescriptor *)descriptor
                device:(id<MTLDevice>)device {
    return @{ @"attributes": @(attributes),
              @"descriptor": descriptor.dictionaryValue,
              @"device": [NSValue valueWithPointer:(__bridge const void * _Nullable)(device)] };
}

- (void)cache:(NSCache *)cache willEvictObject:(id)obj {
    DLog(@"Will evict object %@", obj);
}

@end

@implementation iTermASCIITexture

- (instancetype)initWithAttributes:(iTermASCIITextureAttributes)attributes
                        descriptor:(iTermCharacterSourceDescriptor *)descriptor
                            device:(id<MTLDevice>)device
                          creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull (^)(char, iTermASCIITextureAttributes))creation {
    self = [super init];
    if (self) {
        _parts = (iTermASCIITextureParts *)calloc(128, sizeof(iTermASCIITextureParts));
        _attributes = attributes;
        _textureArray = [[iTermTextureArray alloc] initWithTextureWidth:descriptor.glyphSize.width
                                                          textureHeight:descriptor.glyphSize.height
                                                            arrayLength:iTermASCIITextureCapacity
                                                                   bgra:YES
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

- (void)dealloc {
    free(_parts);
}

@end

@implementation iTermASCIITextureGroup {
    iTermCharacterSourceDescriptor *_descriptor;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
            creationIdentifier:(id)creationIdentifier
                    descriptor:(iTermCharacterSourceDescriptor *)descriptor
                      creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation {
    self = [super init];
    if (self) {
        _device = device;
        _descriptor = descriptor;
        _creationIdentifier = creationIdentifier;
        _creation = [creation copy];
        CGSize temp = [iTermTextureArray atlasSizeForUnitSize:descriptor.glyphSize
                                                  arrayLength:iTermASCIITextureCapacity
                                                  cellsPerRow:NULL];
        _atlasSize = simd_make_float2(temp.width, temp.height);
    }
    return self;
}

- (CGSize)glyphSize {
    return _descriptor.glyphSize;
}

- (iTermASCIITexture *)newASCIITextureForAttributes:(iTermASCIITextureAttributes)attributes {
    return [[iTermASCIITexture alloc] initWithAttributes:attributes
                                              descriptor:_descriptor
                                                  device:_device
                                                creation:_creation];
}

- (iTermASCIITexture *)asciiTextureForAttributes:(iTermASCIITextureAttributes)attributes {
    if (_textures[attributes]) {
        return _textures[attributes];
    }

    __weak __typeof(self) weakSelf = self;
    iTermASCIITexture *texture = [[iTermASCIITextureCache sharedInstance] asciiTextureWithAttributes:attributes
                                                                                          descriptor:_descriptor
                                                                                              device:_device
                                                                                            creation:^iTermASCIITexture *{
                                                                                                DLog(@"Create texture with attributes %@", @(attributes));
                                                                                                return [weakSelf newASCIITextureForAttributes:attributes];
                                                                                            }];
    _textures[attributes] = texture;
    return texture;
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[iTermASCIITextureGroup class]]) {
        return NO;
    }
    iTermASCIITextureGroup *other = object;
    return (CGSizeEqualToSize(other.glyphSize, self.glyphSize) &&
            other.device == _device &&
            [other.creationIdentifier isEqual:_creationIdentifier]);
}

@end

