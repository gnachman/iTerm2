//
//  iTermTextRendererTransientState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/17.
//

#import "iTermTextRendererTransientState.h"
#import "iTermTextRendererTransientState+Private.h"
#import "iTermPIUArray.h"
#import "iTermSubpixelModelBuilder.h"
#import "iTermTexturePage.h"
#import "iTermTexturePageCollection.h"
#import "NSMutableData+iTerm.h"

#include <map>

const vector_float4 iTermIMEColor = simd_make_float4(1, 1, 0, 1);
const vector_float4 iTermAnnotationUnderlineColor = simd_make_float4(1, 1, 0, 1);

namespace iTerm2 {
    class TexturePage;
}

typedef struct {
    size_t piu_index;
    int x;
    int y;
} iTermTextFixup;

// text color component, background color component
typedef std::pair<unsigned char, unsigned char> iTermColorComponentPair;

@implementation iTermTextRendererTransientState {
    // Array of PIUs for each texture page.
    std::map<iTerm2::TexturePage *, iTerm2::PIUArray<iTermTextPIU> *> _pius;

    iTermPreciseTimerStats _stats[iTermTextRendererStatCount];
}

- (void)dealloc {
    for (auto it = _pius.begin(); it != _pius.end(); it++) {
        delete it->second;
    }
}

+ (NSString *)formatTextPIU:(iTermTextPIU)a {
    return [NSString stringWithFormat:
            @"offset=(%@, %@) "
            @"textureOffset=(%@, %@) ",
            @(a.offset.x),
            @(a.offset.y),
            @(a.textureOffset.x),
            @(a.textureOffset.y)];
}

- (void)writeDebugInfoToFolder:(NSURL *)folder {
    [super writeDebugInfoToFolder:folder];

    [_modelData writeToURL:[folder URLByAppendingPathComponent:@"model.bin"] atomically:NO];

    @autoreleasepool {
        NSMutableString *s = [NSMutableString string];
        for (auto entry : _pius) {
            const iTerm2::TexturePage *texturePage = entry.first;
            iTerm2::PIUArray<iTermTextPIU> *piuArray = entry.second;
            [s appendFormat:@"Texture Page with texture %@:\n", texturePage->get_texture().label];
            if (piuArray) {
                for (int j = 0; j < piuArray->size(); j++) {
                    iTermTextPIU &piu = piuArray->get(j);
                    [s appendString:[self.class formatTextPIU:piu]];
                }
            }
        }
        [s writeToURL:[folder URLByAppendingPathComponent:@"non-ascii-pius.txt"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }

    NSString *s = [NSString stringWithFormat:@"backgroundTexture=%@",
                   _backgroundTexture];
    [s writeToURL:[folder URLByAppendingPathComponent:@"state.txt"]
       atomically:NO
         encoding:NSUTF8StringEncoding
            error:NULL];
}

- (iTermPreciseTimerStats *)stats {
    return _stats;
}

- (int)numberOfStats {
    return iTermTextRendererStatCount;
}

- (NSString *)nameForStat:(int)i {
    return [@[ @"text.newQuad",
               @"text.newPIU",
               @"text.newDims",
               @"text.subpixel",
               @"text.draw" ] objectAtIndex:i];
}

- (void)enumerateDraws:(void (^)(const iTermTextPIU *, NSInteger, id<MTLTexture>, vector_uint2, vector_uint2, iTermMetalUnderlineDescriptor))block {
    for (auto const &mapPair : _pius) {
        const iTerm2::TexturePage *const &texturePage = mapPair.first;
        const iTerm2::PIUArray<iTermTextPIU> *const &piuArray = mapPair.second;

        for (size_t i = 0; i < piuArray->get_number_of_segments(); i++) {
            const size_t count = piuArray->size_of_segment(i);
            if (count > 0) {
                block(piuArray->start_of_segment(i),
                      count,
                      texturePage->get_texture(),
                      texturePage->get_atlas_size(),
                      texturePage->get_cell_size(),
                      _nonAsciiUnderlineDescriptor);
            }
        }
    }
}

- (void)willDraw {
    for (auto pair : _pius) {
        iTerm2::TexturePage *page = pair.first;
        page->record_use();
    }
}

- (void)setGlyphKeysData:(iTermData *)glyphKeysData
                   count:(int)count
                     row:(int)row
       markedRangeOnLine:(NSRange)markedRangeOnLine
                 context:(iTermMetalBufferPoolContext *)context
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)glyphKeysData.mutableBytes;

    std::map<int, int> lastRelations;

    for (int x = 0; x < count; x++) {
        if (!glyphKeys[x].drawable) {
            continue;
        }

#warning TODO: Only do double the work if the thin strokes setting depends on color combination.
        [self addGlyphKey:&glyphKeys[x] thinStrokes:YES row:row x:x context:context creation:creation];
        [self addGlyphKey:&glyphKeys[x] thinStrokes:NO row:row x:x context:context creation:creation];
    }
}

- (void)addGlyphKey:(const iTermMetalGlyphKey *)key
        thinStrokes:(BOOL)thinStrokes
                row:(int)row
                  x:(int)x
            context:(iTermMetalBufferPoolContext *)context
           creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    iTermMetalGlyphKey temp = *key;
    temp.thinStrokes = thinStrokes;
    const iTerm2::GlyphKey glyphKey(&temp);
    std::vector<const iTerm2::GlyphEntry *> *entries = _texturePageCollectionSharedPointer.object->find(glyphKey);
    if (!entries) {
        entries = _texturePageCollectionSharedPointer.object->add(x, glyphKey, context, creation);
        if (!entries) {
            return;
        }
    }
    const float cellHeight = self.cellConfiguration.cellSize.height;
    const float cellWidth = self.cellConfiguration.cellSize.width;
    const float yOffset = (self.cellConfiguration.gridSize.height - row - 1) * cellHeight;
    const int width = self.cellConfiguration.gridSize.width;
    for (auto entry : *entries) {
        auto it = _pius.find(entry->_page);
        iTerm2::PIUArray<iTermTextPIU> *array;
        if (it == _pius.end()) {
            array = _pius[entry->_page] = new iTerm2::PIUArray<iTermTextPIU>(_numberOfCells);
        } else {
            array = it->second;
        }
        iTermTextPIU *piu = array->get_next();
        // Build the PIU
        const int &part = entry->_part;
        const int dx = iTermImagePartDX(part);
        const int dy = iTermImagePartDY(part);
        piu->offset = simd_make_float2((x + dx) * cellWidth,
                                       -dy * cellHeight + yOffset);

        MTLOrigin origin = entry->get_origin();
        vector_float2 reciprocal_atlas_size = entry->_page->get_reciprocal_atlas_size();
        piu->textureOffset = simd_make_float2(origin.x * reciprocal_atlas_size.x,
                                              origin.y * reciprocal_atlas_size.y);

        piu->remapColors = !entry->_is_emoji;
        piu->thinStrokes = thinStrokes;
        piu->cellIndex = x + row * (width + 1);
    }
}

- (void)didComplete {
    _texturePageCollectionSharedPointer.object->prune_if_needed();
}

- (nonnull NSMutableData *)modelData  {
    if (_modelData == nil) {
        _modelData = [[NSMutableData alloc] initWithUninitializedLength:sizeof(iTermTextPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height];
    }
    return _modelData;
}

@end

