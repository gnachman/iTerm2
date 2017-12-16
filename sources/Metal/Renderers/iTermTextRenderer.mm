#import "iTermTextRenderer.h"

extern "C" {
#import "DebugLogging.h"
}

#import "iTermMetalCellRenderer.h"

#import "GlyphKey.h"
#import "iTermASCIITexture.h"
#import "iTermMetalBufferPool.h"
#import "iTermSubpixelModelBuilder.h"
#import "iTermTextureArray.h"
#import "NSArray+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import <map>
#import <set>
#import <unordered_map>
#import <vector>

// This is useful when we over-release a texture page.
// TODO: Use shared_ptr or the like, if it can do the job.
#define ENABLE_OWNERSHIP_LOG 0
#if ENABLE_OWNERSHIP_LOG
#define ITOwnershipLog(args...) NSLog
#else
#define ITOwnershipLog(args...)
#endif

namespace iTerm2 {
class TexturePage;
}

typedef struct {
    size_t piu_index;
    int x;
    int y;
} iTermTextFixup;

static vector_uint2 CGSizeToVectorUInt2(const CGSize &size) {
    return simd_make_uint2(size.width, size.height);
}

static const NSInteger iTermTextAtlasCapacity = 16;

namespace iTerm2 {
    // A PIUArray is an array of arrays of iTermTextPIU structs. This avoids giant allocations.
    // It is append-only.
    class PIUArray {
    public:
        PIUArray() : _capacity(1024), _size(0) {
            _arrays.resize(1);
            _arrays.back().reserve(_capacity);
        }

        explicit PIUArray(size_t capacity) : _capacity(capacity), _size(0) {
            _arrays.resize(1);
            _arrays.back().reserve(_capacity);
        }

        iTermTextPIU *get_next() {
            if (_arrays.back().size() == _capacity) {
                _arrays.resize(_arrays.size() + 1);
                _arrays.back().reserve(_capacity);
            }

            std::vector<iTermTextPIU> &array = _arrays.back();
            array.resize(array.size() + 1);
            _size++;
            return &array.back();
        }

        iTermTextPIU &get(const size_t &segment, const size_t &index) {
            return _arrays[segment][index];
        }

        iTermTextPIU &get(const size_t &index) {
            return _arrays[index / _capacity][index % _capacity];
        }

        void push_back(const iTermTextPIU &piu) {
            memmove(get_next(), &piu, sizeof(piu));
        }

        size_t get_number_of_segments() const {
            return _arrays.size();
        }

        const iTermTextPIU *start_of_segment(const size_t segment) const {
            return &_arrays[segment][0];
        }

        size_t size_of_segment(const size_t segment) const {
            return _arrays[segment].size();
        }

        const size_t &size() const {
            return _size;
        }

    private:
        const size_t _capacity;
        size_t _size;
        std::vector<std::vector<iTermTextPIU>> _arrays;
    };

    class TexturePage;

    class TexturePageOwner {
    public:
        virtual bool texture_page_owner_is_glyph_entry() {
            return false;
        }
    };

    class TexturePage {
    public:
        TexturePage(TexturePageOwner *owner,
                    id<MTLDevice> device,
                    int capacity,
                    vector_uint2 cellSize) :
        _capacity(capacity),
        _cell_size(cellSize),
        _count(0),
        _emoji(capacity) {
            retain(owner);
            _textureArray = [[iTermTextureArray alloc] initWithTextureWidth:cellSize.x
                                                              textureHeight:cellSize.y
                                                                arrayLength:capacity
                                                                     device:device];
            _atlas_size = simd_make_uint2(_textureArray.atlasSize.width,
                                          _textureArray.atlasSize.height);
            _reciprocal_atlas_size = 1.0f / simd_make_float2(_atlas_size.x, _atlas_size.y);
        }

        virtual ~TexturePage() {
            ITOwnershipLog(@"OWNERSHIP: Destructor for page %p", this);
        }

        int get_available_count() const {
            return _capacity - _count;
        }

        int add_image(iTermCharacterBitmap *image, bool is_emoji) {
            ITExtraDebugAssert(_count < _capacity);
            [_textureArray setSlice:_count withBitmap:image];
            _emoji[_count] = is_emoji;
            return _count++;
        }

        id<MTLTexture> get_texture() const {
            return _textureArray.texture;
        }

        iTermTextureArray *get_texture_array() const {
            return _textureArray;
        }

        bool get_is_emoji(const int index) const {
            return _emoji[index];
        }

        const vector_uint2 &get_cell_size() const {
            return _cell_size;
        }

        const vector_uint2 &get_atlas_size() const {
            return _atlas_size;
        }

        const vector_float2 &get_reciprocal_atlas_size() const {
            return _reciprocal_atlas_size;
        }

        void retain(TexturePageOwner *owner) {
            _owners[owner]++;
            ITOwnershipLog(@"OWNERSHIP: retain %p as owner of %p with refcount %d", owner, this, (int)_owners[owner]);
        }

        void release(TexturePageOwner *owner) {
            ITOwnershipLog(@"OWNERSHIP: release %p as owner of %p. New refcount for this owner will be %d", owner, this, (int)_owners[owner]-1);
            ITExtraDebugAssert(_owners[owner] > 0);

            auto it = _owners.find(owner);
#if ENABLE_OWNERSHIP_LOG
            if (it == _owners.end()) {
                ITOwnershipLog(@"I have %d owners", (int)_owners.size());
                for (auto pair : _owners) {
                    ITOwnershipLog(@"%p is owner", pair.first);
                }
                ITExtraDebugAssert(it != _owners.end());
            }
#endif
            it->second--;
            if (it->second == 0) {
                _owners.erase(it);
                if (_owners.empty()) {
                    ITOwnershipLog(@"OWNERSHIP: DELETE %p", this);
                    delete this;
                    return;
                }
            }
        }

        void record_use() {
            static long long use_count;
            _last_used = use_count++;
        }

        long long get_last_used() const {
            return _last_used;
        }

        std::map<TexturePageOwner *, int> get_owners() const {
#if ENABLE_OWNERSHIP_LOG
            for (auto pair : _owners) {
                ITExtraDebugAssert(pair.second > 0);
            }
#endif
            return _owners;
        }

        // This is for debugging purposes only.
        int get_retain_count() const {
            int sum = 0;
            for (auto pair : _owners) {
                sum += pair.second;
            }
            return sum;
        }

    private:
        TexturePage();
        TexturePage &operator=(const TexturePage &);
        TexturePage(const TexturePage &);

        iTermTextureArray *_textureArray;
        int _capacity;
        vector_uint2 _cell_size;
        vector_uint2 _atlas_size;
        int _count;
        std::vector<bool> _emoji;
        vector_float2 _reciprocal_atlas_size;
        std::map<TexturePageOwner *, int> _owners;
        long long _last_used;
    };

    struct GlyphEntry : TexturePageOwner {
        GlyphEntry(int part,
                   GlyphKey key,
                   TexturePage *page,
                   int index,
                   bool is_emoji) :
        _part(part),
        _key(key),
        _page(page),
        _index(index),
        _is_emoji(is_emoji),
        _origin([_page->get_texture_array() offsetForIndex:_index]) {
            page->retain(this);
        }

        virtual ~GlyphEntry() {
            _page->release(this);
        }

        const MTLOrigin &get_origin() const {
            return _origin;
        }

        virtual bool texture_page_owner_is_glyph_entry() {
            return true;
        }

        int _part;
        GlyphKey _key;
        TexturePage *_page;
        int _index;
        bool _is_emoji;

    private:
        MTLOrigin _origin;
    };

    class TexturePageCollection : TexturePageOwner {
    private:
        const GlyphEntry *internal_add(int part, const GlyphKey &key, iTermCharacterBitmap *image, bool is_emoji) {
            if (!_openPage) {
                _openPage = new TexturePage(this, _device, _pageCapacity, _cellSize);  // Retains this for _openPage

                // Add to allPages and retain that reference too
                _allPages.insert(_openPage);
                _openPage->retain(this);
            }

            TexturePage *openPage = _openPage;
            ITExtraDebugAssert(_openPage->get_available_count() > 0);
            const GlyphEntry *result = new GlyphEntry(part,
                                                      key,
                                                      openPage,
                                                      openPage->add_image(image, is_emoji),
                                                      is_emoji);
            if (openPage->get_available_count() == 0) {
                openPage->release(this);
                _openPage = NULL;
            }
            return result;
        }

        static bool LRUComparison(TexturePage *a, TexturePage *b) {
            return a->get_last_used() < b->get_last_used();
        }

    public:
        TexturePageCollection(id<MTLDevice> device,
                              const vector_uint2 cellSize,
                              const int pageCapacity,
                              const int maximumSize) :
        _device(device),
        _cellSize(cellSize),
        _pageCapacity(pageCapacity),
        _maximumSize(maximumSize),
        _openPage(NULL)
        { }

        virtual ~TexturePageCollection() {
            if (_openPage) {
                _openPage->release(this);
                _openPage = NULL;
            }
            for (auto it = _pages.begin(); it != _pages.end(); it++) {
                std::vector<const GlyphEntry *> *vector = it->second;
                for (auto glyph_entry : *vector) {
                    delete glyph_entry;
                }
                delete vector;
            }
        }

        std::vector<const GlyphEntry *> *find(const GlyphKey &glyphKey) const {
            auto const it = _pages.find(glyphKey);
            if (it == _pages.end()) {
                return NULL;
            } else {
                return it->second;
            }
        }

        std::vector<const GlyphEntry *> *add(int column,
                                             const GlyphKey &glyphKey,
                                             NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^creator)(int, BOOL *)) {
            BOOL emoji;
            NSDictionary<NSNumber *, iTermCharacterBitmap *> *images = creator(column, &emoji);
            std::vector<const GlyphEntry *> *result = new std::vector<const GlyphEntry *>();
            _pages[glyphKey] = result;
            for (NSNumber *partNumber in images) {
                iTermCharacterBitmap *image = images[partNumber];
                const GlyphEntry *entry = internal_add(partNumber.intValue, glyphKey, image, emoji);
                result->push_back(entry);
            }
            return result;
        }

        const vector_uint2 &get_cell_size() const {
            return _cellSize;
        }

        void set_maximum_size(int maximumSize) {
            _maximumSize = maximumSize;
        }

        void prune_if_needed() {
            if (is_over_maximum_size()) {
#warning Test this code path
                ELog(@"Pruning");
                std::vector<TexturePage *> pages;
                std::copy(_allPages.begin(), _allPages.end(), std::back_inserter(pages));
                std::sort(pages.begin(), pages.end(), TexturePageCollection::LRUComparison);

                for (int i = 0; is_over_maximum_size() && i < pages.size(); i++) {
                    ITOwnershipLog(@"OWNERSHIP: Begin pruning page %p", pages[i]);
                    TexturePage *pageToPrune = pages[i];
                    if (pageToPrune == _openPage) {
                        pageToPrune->release(this);
                        _openPage = NULL;
                    }
                    _allPages.erase(pageToPrune);
                    pageToPrune->release(this);
                    ITExtraDebugAssert(pageToPrune->get_retain_count() > 0);

                    // Make all glyph entries remove their references to the page. Remove our
                    // references to the glyph entries.
                    auto owners = pageToPrune->get_owners();  // map<TexturePageOwner *, int>
                    ITOwnershipLog(@"OWNERSHIP: page %p has %d owners", pageToPrune, (int)owners.size());
                    for (auto pair : owners) {
                        auto owner = pair.first;  // TexturePageOwner *
                        auto count = pair.second;  // int
                        for (int j = 0; j < count; j++) {
                            if (owner->texture_page_owner_is_glyph_entry()) {
                                GlyphEntry *glyph_entry = static_cast<GlyphEntry *>(owner);
                                pageToPrune->release(glyph_entry);
                                _pages.erase(glyph_entry->_key);
                            }
                        }
                    }
                    ITOwnershipLog(@"OWNERSHIP: Done pruning page %p", pageToPrune);
                }
            } else {
                DLog(@"Not pruning");
            }
        }

    private:
        bool is_over_maximum_size() const {
            return _allPages.size() * _pageCapacity > _maximumSize;
        }

        TexturePageCollection &operator=(const TexturePageCollection &);
        TexturePageCollection(const TexturePageCollection &);

        id<MTLDevice> _device;
        const vector_uint2 _cellSize;
        const int _pageCapacity;
        int _maximumSize;
        std::unordered_map<GlyphKey, std::vector<const GlyphEntry *> *> _pages;
        std::set<TexturePage *> _allPages;
        TexturePage *_openPage;
    };
}

@interface iTermTextRendererTransientState ()

@property (nonatomic, readonly) NSData *colorModels;
@property (nonatomic, readonly) NSData *piuData;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) iTermASCIITextureGroup *asciiTextureGroup;
@property (nonatomic) iTerm2::TexturePageCollection *texturePageCollection;
@property (nonatomic) NSInteger numberOfCells;

@end

// text color component, background color component
typedef std::pair<unsigned char, unsigned char> iTermColorComponentPair;

@implementation iTermTextRendererTransientState {
    // Data's bytes contains a C array of iTermMetalBackgroundColorRLE with background colors.
    NSMutableArray<NSData *> *_backgroundColorRLEDataArray;

    // Info about PIUs that need their background colors set. They belong to
    // parts of glyphs that spilled out of their bounds. The actual PIUs
    // belong to _pius, but are missing some fields.
    std::map<iTerm2::TexturePage *, std::vector<iTermTextFixup> *> _fixups;

    // Color models for this frame. Only used when there's no intermediate texture.
    NSMutableData *_colorModels;

    // Key is text, background color component. Value is color model number (0 is 1st, 1 is 2nd, etc)
    // and you can multiply the color model number by 256 to get its starting point in _colorModels.
    // Only used when there's no intermediate texture.
    std::map<iTermColorComponentPair, int> *_colorModelIndexes;

    NSMutableData *_asciiPIUs[iTermASCIITextureAttributesMax * 2];
    NSInteger _asciiInstances[iTermASCIITextureAttributesMax * 2];

    // Array of PIUs for each texture page.
    std::map<iTerm2::TexturePage *, iTerm2::PIUArray *> _pius;
}

- (instancetype)initWithConfiguration:(__kindof iTermRenderConfiguration *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        _backgroundColorRLEDataArray = [NSMutableArray array];
        iTermCellRenderConfiguration *cellConfiguration = configuration;
        if (!cellConfiguration.usingIntermediatePass) {
            _colorModels = [NSMutableData data];
            _colorModelIndexes = new std::map<iTermColorComponentPair, int>();
        }
    }
    return self;
}

- (void)dealloc {
#warning TODO: Look for memory leaks in the C++ objects
    for (auto pair : _fixups) {
        delete pair.second;
    }
    if (_colorModelIndexes) {
        delete _colorModelIndexes;
    }
    for (auto it = _pius.begin(); it != _pius.end(); it++) {
        delete it->second;
    }
}

- (void)enumerateASCIIDraws:(void (^)(const iTermTextPIU *, NSInteger, id<MTLTexture>, vector_uint2, vector_uint2))block {
    for (int i = 0; i < iTermASCIITextureAttributesMax * 2; i++) {
        if (_asciiInstances[i]) {
            iTermASCIITexture *asciiTexture = [_asciiTextureGroup asciiTextureForAttributes:(iTermASCIITextureAttributes)i];
            ITBetaAssert(asciiTexture, @"nil ascii texture for attributes %d", i);
            block((iTermTextPIU *)_asciiPIUs[i].mutableBytes,
                  _asciiInstances[i],
                  asciiTexture.textureArray.texture,
                  CGSizeToVectorUInt2(asciiTexture.textureArray.atlasSize),
                  CGSizeToVectorUInt2(_asciiTextureGroup.cellSize));
        }
    }
}

- (void)enumerateNonASCIIDraws:(void (^)(const iTermTextPIU *, NSInteger, id<MTLTexture>, vector_uint2, vector_uint2))block {
    for (auto const &mapPair : _pius) {
        const iTerm2::TexturePage *const &texturePage = mapPair.first;
        const iTerm2::PIUArray *const &piuArray = mapPair.second;

        for (size_t i = 0; i < piuArray->get_number_of_segments(); i++) {
            const size_t count = piuArray->size_of_segment(i);
            if (count > 0) {
                block(piuArray->start_of_segment(i),
                      count,
                      texturePage->get_texture(),
                      texturePage->get_atlas_size(),
                      texturePage->get_cell_size());
            }
        }
    }
}

- (void)enumerateDraws:(void (^)(const iTermTextPIU *, NSInteger, id<MTLTexture>, vector_uint2, vector_uint2))block {
    [self enumerateNonASCIIDraws:block];
    [self enumerateASCIIDraws:block];
}

- (void)willDraw {
    DLog(@"WILL DRAW %@", self);
    // Fix up the background color of parts of glyphs that are drawn outside their cell. Add to the
    // correct page's PIUs.
    const int numRows = _backgroundColorRLEDataArray.count;
    const int width = self.cellConfiguration.gridSize.width;
    for (auto pair : _fixups) {
        iTerm2::TexturePage *page = pair.first;
        std::vector<iTermTextFixup> *fixups = pair.second;
        for (auto fixup : *fixups) {
            iTerm2::PIUArray &piuArray = *_pius[page];
            iTermTextPIU &piu = piuArray.get(fixup.piu_index);

            // Set fields in piu
            if (fixup.y >= 0 && fixup.y < numRows && fixup.x >= 0 && fixup.x < width) {
                NSData *data = _backgroundColorRLEDataArray[fixup.y];
                const iTermMetalBackgroundColorRLE *backgroundRLEs = (iTermMetalBackgroundColorRLE *)data.bytes;
                // find RLE for index fixup.x
                const int rleCount = data.length / sizeof(iTermMetalBackgroundColorRLE);
                const iTermMetalBackgroundColorRLE &rle = *std::lower_bound(backgroundRLEs,
                                                                            backgroundRLEs + rleCount,
                                                                            static_cast<unsigned short>(fixup.x));
                piu.backgroundColor = rle.color;
                if (_colorModels) {
                    piu.colorModelIndex = [self colorModelIndexForPIU:&piu];
                }
            } else {
                // Offscreen
                piu.backgroundColor = _defaultBackgroundColor;
            }
        }
        delete fixups;
    }

    _fixups.clear();

    for (auto pair : _pius) {
        iTerm2::TexturePage *page = pair.first;
        page->record_use();
    }
    DLog(@"END WILL DRAW");
}

static iTermTextPIU *iTermTextRendererTransientStateAddASCIIPart(iTermTextPIU *piuArray,
                                                                 int i,
                                                                 char code,
                                                                 float w,
                                                                 float h,
                                                                 iTermASCIITexture *texture,
                                                                 float cellWidth,
                                                                 int x,
                                                                 float yOffset,
                                                                 iTermASCIITextureOffset offset,
                                                                 vector_float4 textColor,
                                                                 vector_float4 backgroundColor,
                                                                 iTermMetalGlyphAttributesUnderline underlineStyle,
                                                                 vector_float4 underlineColor) {
    iTermTextPIU *piu = &piuArray[i];
    piu->offset = simd_make_float2(x * cellWidth,
                                   yOffset);
    MTLOrigin origin = [texture.textureArray offsetForIndex:iTermASCIITextureIndexOfCode(code, offset)];
    piu->textureOffset = (vector_float2){ origin.x * w, origin.y * h };
    piu->textColor = textColor;
    piu->backgroundColor = backgroundColor;
    piu->remapColors = YES;
    piu->underlineStyle = underlineStyle;
    piu->underlineColor = underlineColor;
    return piu;
}

- (void)addASCIICellToPIUsForCode:(char)code
                                x:(int)x
                          yOffset:(float)yOffset
                                w:(float)w
                                h:(float)h
                        cellWidth:(float)cellWidth
                       asciiAttrs:(iTermASCIITextureAttributes)asciiAttrs
                       attributes:(const iTermMetalGlyphAttributes *)attributes {
    iTermASCIITexture *texture = [_asciiTextureGroup asciiTextureForAttributes:asciiAttrs];
    NSMutableData *data = _asciiPIUs[asciiAttrs];
    if (!data) {
        data = [NSMutableData dataWithCapacity:_numberOfCells * sizeof(iTermTextPIU) * iTermASCIITextureOffsetCount];
        _asciiPIUs[asciiAttrs] = data;
    }

    iTermTextPIU *piuArray = (iTermTextPIU *)data.mutableBytes;
    iTermASCIITextureParts parts = texture.parts[(size_t)code];
    vector_float4 underlineColor = { 0, 0, 0, 0 };
    if (attributes[x].underlineStyle != iTermMetalGlyphAttributesUnderlineNone) {
        underlineColor = _asciiUnderlineDescriptor.color.w > 0 ? _asciiUnderlineDescriptor.color : attributes[x].foregroundColor;
    }
    // Add PIU for left overflow
    iTermTextPIU *piu;
    if (parts & iTermASCIITexturePartsLeft) {
        if (x > 0) {
            // Normal case
            piu = iTermTextRendererTransientStateAddASCIIPart(piuArray,
                                                              _asciiInstances[asciiAttrs]++,
                                                              code,
                                                              w,
                                                              h,
                                                              texture,
                                                              cellWidth,
                                                              x - 1,
                                                              yOffset,
                                                              iTermASCIITextureOffsetLeft,
                                                              attributes[x].foregroundColor,
                                                              attributes[x - 1].backgroundColor,
                                                              iTermMetalGlyphAttributesUnderlineNone,
                                                              underlineColor);
        } else {
            // Intrusion into left margin
            piu = iTermTextRendererTransientStateAddASCIIPart(piuArray,
                                                              _asciiInstances[asciiAttrs]++,
                                                              code,
                                                              w,
                                                              h,
                                                              texture,
                                                              cellWidth,
                                                              x - 1,
                                                              yOffset,
                                                              iTermASCIITextureOffsetLeft,
                                                              attributes[x].foregroundColor,
                                                              _defaultBackgroundColor,
                                                              iTermMetalGlyphAttributesUnderlineNone,
                                                              underlineColor);
        }
        if (_colorModels) {
            piu->colorModelIndex = [self colorModelIndexForPIU:piu];
        }
    }

    // Add PIU for center part, which is always present
    piu = iTermTextRendererTransientStateAddASCIIPart(piuArray,
                                                      _asciiInstances[asciiAttrs]++,
                                                      code,
                                                      w,
                                                      h,
                                                      texture,
                                                      cellWidth,
                                                      x,
                                                      yOffset,
                                                      iTermASCIITextureOffsetCenter,
                                                      attributes[x].foregroundColor,
                                                      attributes[x].backgroundColor,
                                                      attributes[x].underlineStyle,
                                                      underlineColor);
    if (_colorModels) {
        piu->colorModelIndex = [self colorModelIndexForPIU:piu];
    }

    // Add PIU for right overflow
    if (parts & iTermASCIITexturePartsRight) {
        const int lastColumn = self.cellConfiguration.gridSize.width - 1;
        if (x < lastColumn) {
            // Normal case
            piu = iTermTextRendererTransientStateAddASCIIPart(piuArray,
                                                              _asciiInstances[asciiAttrs]++,
                                                              code,
                                                              w,
                                                              h,
                                                              texture,
                                                              cellWidth,
                                                              x + 1,
                                                              yOffset,
                                                              iTermASCIITextureOffsetRight,
                                                              attributes[x].foregroundColor,
                                                              attributes[x + 1].backgroundColor,
                                                              iTermMetalGlyphAttributesUnderlineNone,
                                                              underlineColor);
        } else {
            // Intrusion into right margin
            piu = iTermTextRendererTransientStateAddASCIIPart(piuArray,
                                                              _asciiInstances[asciiAttrs]++,
                                                              code,
                                                              w,
                                                              h,
                                                              texture,
                                                              cellWidth,
                                                              x + 1,
                                                              yOffset,
                                                              iTermASCIITextureOffsetRight,
                                                              attributes[x].foregroundColor,
                                                              _defaultBackgroundColor,
                                                              iTermMetalGlyphAttributesUnderlineNone,
                                                              underlineColor);
        }
        if (_colorModels) {
            piu->colorModelIndex = [self colorModelIndexForPIU:piu];
        }
    }
}

static inline BOOL GlyphKeyCanTakeASCIIFastPath(const iTermMetalGlyphKey &glyphKey) {
    return (glyphKey.code <= iTermASCIITextureMaximumCharacter &&
            glyphKey.code >= iTermASCIITextureMinimumCharacter &&
            !glyphKey.isComplex &&
            !glyphKey.boxDrawing &&
            !glyphKey.image);
}

- (void)setGlyphKeysData:(NSData *)glyphKeysData
                   count:(int)count
          attributesData:(NSData *)attributesData
                     row:(int)row
  backgroundColorRLEData:(nonnull NSData *)backgroundColorRLEData
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation {
    DLog(@"BEGIN setGlyphKeysData for %@", self);
    ITDebugAssert(row == _backgroundColorRLEDataArray.count);
    [_backgroundColorRLEDataArray addObject:backgroundColorRLEData];
    const iTermMetalGlyphKey *glyphKeys = (iTermMetalGlyphKey *)glyphKeysData.bytes;
    const iTermMetalGlyphAttributes *attributes = (iTermMetalGlyphAttributes *)attributesData.bytes;
    vector_float2 asciiCellSize = 1.0 / _asciiTextureGroup.atlasSize;
    const float cellHeight = self.cellConfiguration.cellSize.height;
    const float cellWidth = self.cellConfiguration.cellSize.width;
    const float yOffset = (self.cellConfiguration.gridSize.height - row - 1) * cellHeight;

    std::map<int, int> lastRelations;
    BOOL havePrevious = NO;
    for (int x = 0; x < count; x++) {
        if (!glyphKeys[x].drawable) {
            continue;
        }
        if (GlyphKeyCanTakeASCIIFastPath(glyphKeys[x])) {
            // ASCII fast path
            iTermASCIITextureAttributes asciiAttrs = iTermASCIITextureAttributesFromGlyphKeyTypeface(glyphKeys[x].typeface,
                                                                                                     glyphKeys[x].thinStrokes);
            [self addASCIICellToPIUsForCode:glyphKeys[x].code
                                          x:x
                                    yOffset:yOffset
                                          w:asciiCellSize.x
                                          h:asciiCellSize.y
                                  cellWidth:cellWidth
                                 asciiAttrs:asciiAttrs
                                 attributes:attributes];
            havePrevious = NO;
        } else {
            // Non-ASCII slower path
            const iTerm2::GlyphKey glyphKey(&glyphKeys[x]);
            std::vector<const iTerm2::GlyphEntry *> *entries = _texturePageCollection->find(glyphKey);
            if (!entries) {
                entries = _texturePageCollection->add(x, glyphKey, creation);
                if (!entries) {
                    continue;
                }
            }
            for (auto entry : *entries) {
                auto it = _pius.find(entry->_page);
                iTerm2::PIUArray *array;
                if (it == _pius.end()) {
                    array = _pius[entry->_page] = new iTerm2::PIUArray(_numberOfCells);
                } else {
                    array = it->second;
                }
                iTermTextPIU *piu = array->get_next();
                // Build the PIU
                const int &part = entry->_part;
                const int dx = ImagePartDX(part);
                const int dy = ImagePartDY(part);
                piu->offset = simd_make_float2((x + dx) * cellWidth,
                                               -dy * cellHeight + yOffset);
                MTLOrigin origin = entry->get_origin();
                vector_float2 reciprocal_atlas_size = entry->_page->get_reciprocal_atlas_size();
                piu->textureOffset = simd_make_float2(origin.x * reciprocal_atlas_size.x,
                                                      origin.y * reciprocal_atlas_size.y);
                piu->textColor = attributes[x].foregroundColor;
                piu->remapColors = !entry->_is_emoji;
                piu->underlineStyle = attributes[x].underlineStyle;
                piu->underlineColor = _nonAsciiUnderlineDescriptor.color.w > 1 ? _nonAsciiUnderlineDescriptor.color : piu->textColor;

                // Set color info or queue for fixup since color info may not exist yet.
                if (entry->_part == iTermTextureMapMiddleCharacterPart) {
                    piu->backgroundColor = attributes[x].backgroundColor;
                    if (_colorModels) {
                        piu->colorModelIndex = [self colorModelIndexForPIU:piu];
                    }
                } else {
                    iTermTextFixup fixup = {
                        .piu_index = array->size() - 1,
                        .x = x + dx,
                        .y = row + dy,
                    };
                    std::vector<iTermTextFixup> *fixups = _fixups[entry->_page];
                    if (fixups == nullptr) {
                        fixups = new std::vector<iTermTextFixup>();
                        _fixups[entry->_page] = fixups;
                    }
                    fixups->push_back(fixup);
                }
            }
        }
    }
    DLog(@"END setGlyphKeysData for %@", self);
}

- (vector_int3)colorModelIndexForPIU:(iTermTextPIU *)piu {
    iTermColorComponentPair redPair = std::make_pair(piu->textColor.x * 255,
                                                     piu->backgroundColor.x * 255);
    iTermColorComponentPair greenPair = std::make_pair(piu->textColor.y * 255,
                                                       piu->backgroundColor.y * 255);
    iTermColorComponentPair bluePair = std::make_pair(piu->textColor.z * 255,
                                                      piu->backgroundColor.z * 255);
    vector_int3 result;
    auto it = _colorModelIndexes->find(redPair);
    if (it == _colorModelIndexes->end()) {
        result.x = [self allocateColorModelForColorPair:redPair];
    } else {
        result.x = it->second;
    }
    it = _colorModelIndexes->find(greenPair);
    if (it == _colorModelIndexes->end()) {
        result.y = [self allocateColorModelForColorPair:greenPair];
    } else {
        result.y = it->second;
    }
    it = _colorModelIndexes->find(bluePair);
    if (it == _colorModelIndexes->end()) {
        result.z = [self allocateColorModelForColorPair:bluePair];
    } else {
        result.z = it->second;
    }
    return result;
}

- (int)allocateColorModelForColorPair:(iTermColorComponentPair)colorPair {
    int i = _colorModelIndexes->size();
    iTermSubpixelModel *model = [[iTermSubpixelModelBuilder sharedInstance] modelForForegoundColor:colorPair.first / 255.0
                                                                                   backgroundColor:colorPair.second / 255.0];
    [_colorModels appendData:model.table];
    (*_colorModelIndexes)[colorPair] = i;
    return i;
}

- (void)didComplete {
    DLog(@"BEGIN didComplete for %@", self);
    _texturePageCollection->prune_if_needed();
    DLog(@"END didComplete");
}

- (nonnull NSMutableData *)modelData  {
    if (_modelData == nil) {
        _modelData = [[NSMutableData alloc] initWithUninitializedLength:sizeof(iTermTextPIU) * self.cellConfiguration.gridSize.width * self.cellConfiguration.gridSize.height];
    }
    return _modelData;
}

@end

@interface iTermTextRendererCachedQuad : NSObject
@property (nonatomic, strong) id<MTLBuffer> quad;
@property (nonatomic) CGSize textureSize;
@property (nonatomic) CGSize cellSize;
@end

@implementation iTermTextRendererCachedQuad

- (BOOL)isEqual:(id)object {
    iTermTextRendererCachedQuad *other = [iTermTextRendererCachedQuad castFrom:object];
    if (!other) {
        return NO;
    }

    return (CGSizeEqualToSize(_textureSize, other->_textureSize) &&
            CGSizeEqualToSize(_cellSize, other->_cellSize));
}

@end

@implementation iTermTextRenderer {
    iTermMetalCellRenderer *_cellRenderer;
    id<MTLBuffer> _models;
    iTermASCIITextureGroup *_asciiTextureGroup;

    iTerm2::TexturePageCollection *_texturePageCollection;
    NSMutableArray<iTermTextRendererCachedQuad *> *_quadCache;

    iTermMetalBufferPool *_emptyBuffers;
    iTermMetalBufferPool *_verticesPool;
    iTermMetalBufferPool *_dimensionsPool;
    iTermMetalMixedSizeBufferPool *_piuPool;
    iTermMetalMixedSizeBufferPool *_subpixelModelPool;
}

+ (NSData *)subpixelModelData {
    static NSData *subpixelModelData;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableData *data = [NSMutableData data];
        // The fragment function assumes we use the value 17 here. It's
        // convenient that 17 evenly divides 255 (17 * 15 = 255).
        float stride = 255.0/17.0;
        for (float textColor = 0; textColor < 256; textColor += stride) {
            for (float backgroundColor = 0; backgroundColor < 256; backgroundColor += stride) {
                iTermSubpixelModel *model = [[iTermSubpixelModelBuilder sharedInstance] modelForForegoundColor:MIN(MAX(0, textColor / 255.0), 1)
                                                                                               backgroundColor:MIN(MAX(0, backgroundColor / 255.0), 1)];
                [data appendData:model.table];
            }
        }
        subpixelModelData = data;
    });
    return subpixelModelData;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    return iTermMetalFrameDataStatPqCreateTextTS;
}

- (id<MTLBuffer>)subpixelModelsForState:(iTermTextRendererTransientState *)tState {
    if (tState.colorModels) {
        if (tState.colorModels.length == 0) {
            // Blank screen, emoji-only screen, etc. The buffer won't get accessed but it can't be nil.
            return [_emptyBuffers requestBufferFromContext:tState.poolContext];
        }
        // Return a color model with exactly the fg/bg combos on screen.
        return [_subpixelModelPool requestBufferFromContext:tState.poolContext
                                                       size:tState.colorModels.length
                                                      bytes:tState.colorModels.bytes];
    }

    // Use a generic color model for blending. No need to use a buffer pool here because this is only
    // created once.
    if (_models == nil) {
        NSData *subpixelModelData = [iTermTextRenderer subpixelModelData];
        _models = [_cellRenderer.device newBufferWithBytes:subpixelModelData.bytes
                                                    length:subpixelModelData.length
                                                   options:MTLResourceStorageModeManaged];
        _models.label = @"Subpixel models";
    }
    return _models;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _cellRenderer = [[iTermMetalCellRenderer alloc] initWithDevice:device
                                                    vertexFunctionName:@"iTermTextVertexShader"
                                                  fragmentFunctionName:@"iTermTextFragmentShader"
                                                              blending:YES
                                                        piuElementSize:sizeof(iTermTextPIU)
                                                   transientStateClass:[iTermTextRendererTransientState class]];
        _quadCache = [NSMutableArray array];
        _emptyBuffers = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:1];
        _verticesPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermVertex) * 6];
        _dimensionsPool = [[iTermMetalBufferPool alloc] initWithDevice:device bufferSize:sizeof(iTermTextureDimensions)];

        // The capacity here is a guess, and it's possible that it's nowhere near enough, but there's
        // significant risk of it using a crazy amount of memory. The largest array could be the
        // number of draws, although that's unlikely. That would happen if you had a character that
        // overflowed its bounds by the maximum amount that repeated on every cell. Then you'd have
        // one big buffer of size iTermTextureMapMaxCharacterParts^2 * number of cells, which could
        // be on the order of 2 million entries times O(100 bytes) for a PIU = 200 megabytes per. Of
        // course, you'd never have more than max-frames-in-flight of those allocated at once. Given
        // 3 frames in flight, we might use 600 megabytes in the worst case.
        //
#warning: TODO: Prevent runaway PIU buffer sizes. Cut them off at something reasonable like 10 megs.
        _piuPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device capacity:512 name:@"text PIU"];

        _subpixelModelPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                          capacity:512
                                                                              name:@"subpixel PIU"];
    }
    return self;
}

- (void)dealloc {
    delete _texturePageCollection;
}

- (__kindof iTermMetalRendererTransientState * _Nonnull)createTransientStateForCellConfiguration:(iTermCellRenderConfiguration *)configuration
                                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    // NOTE: Any time a glyph overflows its bounds into a neighboring cell it's possible the strokes will intersect.
    // I haven't thought of a way to make that look good yet without having to do one draw pass per overflow glyph that
    // blends using the output of the preceding passes.
    _cellRenderer.fragmentFunctionName = configuration.usingIntermediatePass ? @"iTermTextFragmentShaderWithBlending" : @"iTermTextFragmentShaderSolidBackground";
    __kindof iTermMetalCellRendererTransientState * _Nonnull transientState =
        [_cellRenderer createTransientStateForCellConfiguration:configuration
                                              commandBuffer:commandBuffer];
    [self initializeTransientState:transientState
                     commandBuffer:commandBuffer];
    return transientState;

}

- (void)initializeTransientState:(iTermTextRendererTransientState *)tState
                   commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (_texturePageCollection != NULL) {
#warning TODO: Freeing the texture page collection without using reference counting will leave transient states with dangling pointers if we ever have more than one frame in flight.
        const vector_uint2 &oldSize = _texturePageCollection->get_cell_size();
        CGSize newSize = tState.cellConfiguration.cellSize;
        if (oldSize.x != newSize.width || oldSize.y != newSize.height) {
            delete _texturePageCollection;
            _texturePageCollection = NULL;
        }
    }
    // This seems like a good number 🤷‍♂️
    const int maximumSize = 4096;
    if (!_texturePageCollection) {
        _texturePageCollection = new iTerm2::TexturePageCollection(_cellRenderer.device,
                                                                   simd_make_uint2(tState.cellConfiguration.cellSize.width,
                                                                                   tState.cellConfiguration.cellSize.height),
                                                                   iTermTextAtlasCapacity,
                                                                   maximumSize);
    } else {
        _texturePageCollection->set_maximum_size(maximumSize);
    }

    tState.device = _cellRenderer.device;
    tState.asciiTextureGroup = _asciiTextureGroup;
    tState.texturePageCollection = _texturePageCollection;
    tState.numberOfCells = tState.cellConfiguration.gridSize.width * tState.cellConfiguration.gridSize.height;
}

- (id<MTLBuffer>)quadOfSize:(CGSize)size
                textureSize:(CGSize)textureSize
                poolContext:(iTermMetalBufferPoolContext *)poolContext {
    iTermTextRendererCachedQuad *entry = [[iTermTextRendererCachedQuad alloc] init];
    entry.cellSize = size;
    entry.textureSize = textureSize;
    NSInteger index = [_quadCache indexOfObject:entry];
    if (index != NSNotFound) {
        return _quadCache[index].quad;
    }

    const float vw = static_cast<float>(size.width);
    const float vh = static_cast<float>(size.height);

    const float w = size.width / textureSize.width;
    const float h = size.height / textureSize.height;

    const iTermVertex vertices[] = {
        // Pixel Positions, Texture Coordinates
        { { vw,  0 }, { w, 0 } },
        { { 0,   0 }, { 0, 0 } },
        { { 0,  vh }, { 0, h } },

        { { vw,  0 }, { w, 0 } },
        { { 0,  vh }, { 0, h } },
        { { vw, vh }, { w, h } },
    };
    entry.quad = [_verticesPool requestBufferFromContext:poolContext
                                               withBytes:vertices
                                          checkIfChanged:YES];
    [_quadCache addObject:entry];
    // It's useful to hold a quad for ascii and one for non-ascii.
    if (_quadCache.count > 2) {
        [_quadCache removeObjectAtIndex:0];
    }

    return entry.quad;
}

- (void)drawWithRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder
               transientState:(__kindof iTermMetalCellRendererTransientState *)transientState {
    iTermTextRendererTransientState *tState = transientState;
    tState.vertexBuffer.label = @"Text vertex buffer";
    tState.offsetBuffer.label = @"Offset";
    const float scale = tState.cellConfiguration.scale;

    // The vertex buffer's texture coordinates depend on the texture map's atlas size so it must
    // be initialized after the texture map.
    __block NSInteger totalInstances = 0;
    iTermTextureDimensions previousTextureDimensions;
    id<MTLBuffer> previousTextureDimensionsBuffer = nil;

    [tState enumerateDraws:^(const iTermTextPIU *pius, NSInteger instances, id<MTLTexture> texture, vector_uint2 textureSize, vector_uint2 cellSize) {
        totalInstances += instances;
        tState.vertexBuffer = [self quadOfSize:tState.cellConfiguration.cellSize
                                   textureSize:CGSizeMake(textureSize.x, textureSize.y)
                                   poolContext:tState.poolContext];
        id<MTLBuffer> piuBuffer = [_piuPool requestBufferFromContext:tState.poolContext
                                                                size:sizeof(iTermTextPIU) * instances
                                                               bytes:pius];
        ITDebugAssert(piuBuffer);
        piuBuffer.label = @"Text PIUs";

        NSDictionary *textures = @{ @(iTermTextureIndexPrimary): texture };
        if (tState.cellConfiguration.usingIntermediatePass) {
            textures = [textures dictionaryBySettingObject:tState.backgroundTexture forKey:@(iTermTextureIndexBackground)];
        }
        iTermTextureDimensions textureDimensions = {
            .textureSize = simd_make_float2(textureSize.x, textureSize.y),
            .cellSize = simd_make_float2(cellSize.x, cellSize.y),
            .underlineOffset = cellSize.y - (tState.asciiUnderlineDescriptor.offset * scale),
            .underlineThickness = tState.asciiUnderlineDescriptor.thickness * scale,
            .scale = scale
        };

        // These tend to get reused so avoid changing the buffer if it is the same as the last one.
        id<MTLBuffer> textureDimensionsBuffer;
        if (previousTextureDimensionsBuffer != nil &&
            !memcmp(&textureDimensions, &previousTextureDimensions, sizeof(textureDimensions))) {
            textureDimensionsBuffer = previousTextureDimensionsBuffer;
        } else {
            textureDimensionsBuffer = [_dimensionsPool requestBufferFromContext:tState.poolContext
                                                                      withBytes:&textureDimensions
                                                                 checkIfChanged:YES];
            textureDimensionsBuffer.label = @"Texture dimensions";
        }

        [_cellRenderer drawWithTransientState:tState
                                renderEncoder:renderEncoder
                             numberOfVertices:6
                                 numberOfPIUs:instances
                                vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                                 @(iTermVertexInputIndexPerInstanceUniforms): piuBuffer,
                                                 @(iTermVertexInputIndexOffset): tState.offsetBuffer }
                              fragmentBuffers:@{ @(iTermFragmentBufferIndexColorModels): [self subpixelModelsForState:tState],
                                                 @(iTermFragmentInputIndexTextureDimensions): textureDimensionsBuffer }
                                     textures:textures];
    }];
}

- (void)setASCIICellSize:(CGSize)cellSize
      creationIdentifier:(id)creationIdentifier
                creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation {
    iTermASCIITextureGroup *replacement = [[iTermASCIITextureGroup alloc] initWithCellSize:cellSize
                                                                                    device:_cellRenderer.device
                                                                        creationIdentifier:(id)creationIdentifier
                                                                                  creation:creation];
    if (![replacement isEqual:_asciiTextureGroup]) {
        _asciiTextureGroup = replacement;
    }
}

@end
