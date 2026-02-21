//
//  LineBlock.m
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

extern "C" {
#import "LineBlock.h"
#import "LineBlock+Private.h"
#import "LineBlock+SwiftInterop.h"

#import "DebugLogging.h"
#import "FindContext.h"
#import "iTermCharacterBuffer.h"
#import "iTermCoreSearch.h"
#import "iTermExternalAttributeIndex.h"
#import "iTermLegacyAtomicMutableArrayOfWeakObjects.h"
#import "iTermMalloc.h"
#import "iTermMetadata.h"
#import "iTermWeakBox.h"
#import "LineBlockMetadataArray.h"
#import "LineBufferHelpers.h"
#import "NSArray+iTerm.h"
#import "NSBundle+iTerm.h"
#import "NSObject+iTerm.h"
#import "RegexKitLite.h"
#import "iTermAdvancedSettingsModel.h"
}

// BEGIN C++ HEADERS - No C headers here!
#include <atomic>
#include <functional>
#include <mutex>
#include <vector>
#include "unordered_dense/unordered_dense.h"

static BOOL gEnableDoubleWidthCharacterLineCache = NO;
static BOOL gUseCachingNumberOfLines = NO;

NSString *const kLineBlockRawBufferV1Key = @"Raw Buffer";  // v1 - uses legacy screen_char_t format.
NSString *const kLineBlockRawBufferV2Key = @"Raw Buffer v2";  // v2 - used 0xf000-0xf003 for DWC_SKIP and friends.
NSString *const kLineBlockRawBufferV3Key = @"Raw Buffer v3";  // v3 - uses 0x0001-0x0004 for DWC_SKIP and friends
NSString *const kLineBlockRawBufferV4Key = @"Raw Buffer v4";  // v4 - Like v3 but could be compressed. No longer supported because overhead from compression-related abstractions was too slow.
NSString *const kLineBlockBufferStartOffsetKey = @"Buffer Start Offset";
NSString *const kLineBlockStartOffsetKey = @"Start Offset";
NSString *const kLineBlockFirstEntryKey = @"First Entry";
NSString *const kLineBlockBufferSizeKey = @"Buffer Size";
NSString *const kLineBlockCLLKey = @"Cumulative Line Lengths";
NSString *const kLineBlockIsPartialKey = @"Is Partial";
NSString *const kLineBlockMetadataKey = @"Metadata";
NSString *const kLineBlockMayHaveDWCKey = @"May Have Double Width Character";
NSString *const kLineBlockGuid = @"GUID";
dispatch_queue_t gDeallocQueue;

#ifdef DEBUG_SEARCH
#define SearchLog(args...) NSLog(args)
#else
#define SearchLog(args...)
#endif

@protocol iTermLineBlockMutationCertificate
- (int *)mutableCumulativeLineLengths;
- (void)setCumulativeLineLengthsCapacity:(int)capacity;
- (screen_char_t *)mutableRawBuffer;
- (void)setRawBufferCapacity:(size_t)count;
- (void)invalidate;
@end

// ONLY -validMutationCertificate should create this!
@interface iTermLineBlockMutator: NSObject<iTermLineBlockMutationCertificate>
- (instancetype)initWithLineBlock:(LineBlock *)lineBlock NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

static NSString *LineBlockLocationDescription(LineBlockLocation location) {
    return [NSString stringWithFormat:@"<LineBlockLocation found=%@ prev=%@ numEmptyLines=%@ index=%@ length=%@>",
            @(location.found),
            @(location.prev),
            @(location.numEmptyLines),
            @(location.index),
            @(location.length)];
}

static LineBlockLocation LineBlockMakeLocation(int offset, int length, int index) {
    return (LineBlockLocation){
        .prev = offset,
        .length = length,
        .index = index
    };
}

void EnableDoubleWidthCharacterLineCache() {
    gEnableDoubleWidthCharacterLineCache = YES;
}

struct iTermNumFullLinesCacheKey {
    int offset;
    int length;
    int width;

    iTermNumFullLinesCacheKey(const int &xOffset,
                              const int &xLength,
                              const int &xWidth) :
        offset(xOffset),
        length(xLength),
        width(xWidth) { }

    bool operator==(const iTermNumFullLinesCacheKey &other) const {
        return (offset == other.offset &&
                length == other.length &&
                width == other.width);
    }
};

struct iTermNumFullLinesCacheKeyHasher {
    std::size_t operator()(const iTermNumFullLinesCacheKey& k) const {
        // djb2
        std::size_t hash = 5381;
        hash *= 33;
        hash ^= k.offset;
        hash *= 33;
        hash ^= k.length;
        hash *= 33;
        hash ^= k.width;
        return hash;
    }
};

static std::recursive_mutex gLineBlockMutex;



// Use iTermAssignToConstPointer if you need to change anything that is `const T * const` to make
// these calls auditable to ensure we call validMutationCertificate appropriately.
static inline void ModifyLineBlock(LineBlock *self,
                                   std::function<void(id<iTermLineBlockMutationCertificate>)> lambda) {
    if (!self.hasBeenCopied) {
        lambda([self validMutationCertificate]);
        return;
    }

    {
        std::lock_guard<std::recursive_mutex> lock(gLineBlockMutex);
        lambda([self validMutationCertificate]);
    }
}

@implementation LineBlock {
    // Keys are (offset from _characterBuffer.pointer, length to examine, width).
    ankerl::unordered_dense::map<iTermNumFullLinesCacheKey, int, iTermNumFullLinesCacheKeyHasher> _numberOfFullLinesCache;
}

@synthesize progenitor = _progenitor;
@synthesize absoluteBlockNumber = _absoluteBlockNumber;

static std::atomic<NSInteger> nextGeneration(1);

NS_INLINE NSInteger iTermAllocateGeneration(void) {
    return nextGeneration.fetch_add(1, std::memory_order_relaxed);
}

NS_INLINE void iTermLineBlockDidChange(__unsafe_unretained LineBlock *lineBlock, const char * reason) {
    const NSInteger g = iTermAllocateGeneration();
    lineBlock->_generation = g;
}

- (instancetype)initWithCharacterBuffer:(iTermCharacterBuffer *)characterBuffer 
                                   guid:(NSString *)guid {
    self = [super init];
    if (self) {
        _characterBuffer = characterBuffer;
        _guid = guid;
        [self commonInit];
    }
    return self;
}

//static void iTermAssignToConstPointer(void **dest, void *address) {
//    *dest = address;
//}
#define iTermAssignToConstPointer(dest, address) (*(dest) = (address))

- (LineBlock *)initWithRawBufferSize:(int)size
                 absoluteBlockNumber:(long long)absoluteBlockNumber {
    self = [super init];
    if (self) {
        _absoluteBlockNumber = absoluteBlockNumber;
        _characterBuffer = [[iTermCharacterBuffer alloc] initWithSize:size];

        // Allocate enough space for a bunch of 80-character lines. It can grow if needed.
        cll_capacity = 1 + size/80;
        iTermAssignToConstPointer((void **)&cumulative_line_lengths, iTermMalloc(sizeof(int) * cll_capacity));
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithItems:(CTVector(iTermAppendItem) *)items
                    fromIndex:(int)startIndex
                        width:(int)width
          absoluteBlockNumber:(long long)absoluteBlockNumber {
    self = [super init];
    if (self) {
        _absoluteBlockNumber = absoluteBlockNumber;
        int size = 0;
        int lineCount = 1;
        for (int i = startIndex; i < CTVectorCount(items); i++) {
            const iTermAppendItem &item = CTVectorGet(items, i);
            size += item.length;
            if (!item.partial) {
                lineCount++;
            }
        }
        _characterBuffer = [[iTermCharacterBuffer alloc] initWithSize:size];
        cll_capacity = lineCount;
        iTermAssignToConstPointer((void **)&cumulative_line_lengths, iTermMalloc(sizeof(int) * cll_capacity));
        [self commonInit];
        screen_char_t *outPtr = _characterBuffer.mutablePointer;
        cached_numlines_width = -1;
        int cll = 0;
        for (int i = startIndex; i < CTVectorCount(items); i++) {
            const iTermAppendItem &item = CTVectorGet(items, i);
            memcpy(outPtr, item.buffer, item.length * sizeof(screen_char_t));
            outPtr += item.length;
            const int originalLength = cll_entries > 0 ? cll - cumulative_line_lengths[cll_entries - 1] : 0;
            cll += item.length;
            screen_char_t cont = item.continuation;
            cont.code = item.partial ? EOL_SOFT : EOL_HARD;
            if (is_partial) {
                [_metadataArray appendToLastLine:&item.metadata
                                  originalLength:originalLength
                                additionalLength:item.length
                                    continuation:cont];
            } else {
                cll_entries += 1;
                [_metadataArray append:item.metadata continuation:cont];
            }
            cumulative_line_lengths[cll_entries - 1] = cll;
            is_partial = item.partial;
            assert(_metadataArray.numEntries == cll_entries);
        }
    }
    return self;
}

- (void)commonInit {
    _numberOfFullLinesCache.reserve(16);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([iTermAdvancedSettingsModel dwcLineCache]) {
            gEnableDoubleWidthCharacterLineCache = YES;
            gUseCachingNumberOfLines = YES;
        }
        gDeallocQueue = dispatch_queue_create("com.iterm2.lineblock-dealloc", DISPATCH_QUEUE_SERIAL);
    });
    if (!_guid) {
        _guid = [[NSUUID UUID] UUIDString];
    }
    cached_numlines_width = -1;
    _metadataArray = [[LineBlockMetadataArray alloc] initWithCapacity:cll_capacity
                                                          useDWCCache:gEnableDoubleWidthCharacterLineCache];
    assert(_metadataArray != nil);
    static std::atomic<unsigned int> nextIndex(0);
    _index = nextIndex.fetch_add(1, std::memory_order_relaxed);
    [self initializeClients];
}

+ (instancetype)blockWithDictionary:(NSDictionary *)dictionary
                absoluteBlockNumber:(long long)absoluteBlockNumber {
    return [[self alloc] initWithDictionary:dictionary absoluteBlockNumber:absoluteBlockNumber];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
               absoluteBlockNumber:(long long)absoluteBlockNumber {
    self = [super init];
    if (self) {
        _absoluteBlockNumber = absoluteBlockNumber;
        NSArray *requiredKeys = @[ kLineBlockBufferStartOffsetKey,
                                   kLineBlockStartOffsetKey,
                                   kLineBlockFirstEntryKey,
                                   kLineBlockBufferSizeKey,
                                   kLineBlockCLLKey,
                                   kLineBlockMetadataKey,
                                   kLineBlockIsPartialKey,
                                   kLineBlockMayHaveDWCKey ];
        for (NSString *requiredKey in requiredKeys) {
            if (!dictionary[requiredKey]) {
                return nil;
            }
        }

        NSData *data = nil;
        iTermExternalAttributeIndex *migrationIndex = nil;
        if (dictionary[kLineBlockRawBufferV4Key]) {
            data = [self decompressedDataFromV4Data:dictionary[kLineBlockRawBufferV4Key]];
        } else if (dictionary[kLineBlockRawBufferV3Key]) {
            data = dictionary[kLineBlockRawBufferV3Key];
        } else if (dictionary[kLineBlockRawBufferV2Key]) {
            data = [dictionary[kLineBlockRawBufferV2Key] migrateV2ToV3];
            _generation = iTermAllocateGeneration();
        } else if (dictionary[kLineBlockRawBufferV1Key]) {
            data = [dictionary[kLineBlockRawBufferV1Key] migrateV1ToV3:&migrationIndex];
            _generation = iTermAllocateGeneration();
        }
        if (!data || data.length / sizeof(screen_char_t) >= INT_MAX) {
            return nil;
        }
        _characterBuffer = [[iTermCharacterBuffer alloc] initWithData:data];

        [self setBufferStartOffset:[dictionary[kLineBlockBufferStartOffsetKey] intValue]];
        _firstEntry = [dictionary[kLineBlockFirstEntryKey] intValue];
        if (dictionary[kLineBlockGuid]) {
            _guid = [dictionary[kLineBlockGuid] copy];
            DLog(@"Restore block %p with guid %@", self, _guid);
        }
        NSArray *cllArray = dictionary[kLineBlockCLLKey];
        cll_capacity = [cllArray count];
        iTermAssignToConstPointer((void **)&cumulative_line_lengths, iTermMalloc(sizeof(int) * cll_capacity));
        [self commonInit];

        NSArray *metadataArray = dictionary[kLineBlockMetadataKey];

        int startOffset = 0;
        int *mutableCLL = (int *)cumulative_line_lengths;
        for (int i = 0; i < cll_capacity; i++) {
            mutableCLL[i] = [cllArray[i] intValue];
            NSArray *components = metadataArray[i];

            [_metadataArray setEntry:i
                      fromComponents:components
                      migrationIndex:migrationIndex
                         startOffset:startOffset
                              length:cumulative_line_lengths[i] - startOffset];
            startOffset = cumulative_line_lengths[i];
        }
        [_metadataArray increaseCapacityTo:cll_capacity];
        [_metadataArray setFirstIndex:_firstEntry];
        assert(_metadataArray.first == _firstEntry);

        cll_entries = cll_capacity;
        assert(_metadataArray.numEntries == cll_entries);

        is_partial = [dictionary[kLineBlockIsPartialKey] boolValue];
        _mayHaveDoubleWidthCharacter = [dictionary[kLineBlockMayHaveDWCKey] boolValue];
    }
    return self;
}

// NOTE: You must not acquire a lock in dealloc. Assume it is reentrant.
- (void)dealloc {
    if ([self deinitializeClients]) {
        if (cumulative_line_lengths) {
            free((void *)cumulative_line_lengths);
        }
    }
}

- (BOOL)deinitializeClients {
    // It's safe to access owner without a lock. No other object has a valid reference to this
    // object. Therefore, it's impossible for `self.owner` to change after `dealloc` begins.
    __weak LineBlock *owner = self.owner;
    if (owner == nil) {
        return YES;
    }
    // I don't own my memory so I should not free it.
    dispatch_async(dispatch_get_main_queue(), ^{
        std::lock_guard<std::recursive_mutex> lock(gLineBlockMutex);

        // Remove myself from the owner's client list to ensure its list of clients doesn't
        // get too big. Do it asynchronously to avoid reentrant -[LineBlock dealloc] calls
        // since iTermLegacyAtomicMutableArrayOfWeakObjects's methods are not reentrant.
        [owner.clients prune];
    });
    return NO;
}


- (void)sanityCheckMetadataCache {
    for (int i = _firstEntry; i < cll_entries; ++i) {
        [self sanityCheckmetadataCacheForRawLine:i];
    }
}

- (void)sanityCheckmetadataCacheForRawLine:(int)i {
    const LineBlockMetadata *metadata = [_metadataArray metadataAtIndex:i];
    [self sanityCheckBidiDisplayInfoForRawLine:i];
    [metadata->doubleWidthCharacters sanityCheckWithCharacters:_characterBuffer.pointer + _startOffset + (i > 0 ? cumulative_line_lengths[i - 1] : 0)
                                                        length:[self lengthOfRawLine:i]];
    if (metadata->width_for_number_of_wrapped_lines > 0) {
        int actual = [self calculateNumberOfFullLinesWithOffset:[self _lineRawOffset:i]
                                                         length:[self lengthOfRawLine:i]
                                                          width:metadata->width_for_number_of_wrapped_lines
                                                     mayHaveDWC:YES];
        assert(actual == metadata->number_of_wrapped_lines);
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p abs=%@ %@>",
            NSStringFromClass([self class]),
            self,
            @(_absoluteBlockNumber),
            _characterBuffer.shortDescription];
}

- (void)setBufferStartOffset:(ptrdiff_t)offset {
    _startOffset = offset;
    // The cached numlines and cached width are no longer valid.
    [_metadataArray eraseFirstLineCache];
}

- (int)bufferStartOffset {
    return _startOffset;
}

- (int)rawBufferSize {
    return _characterBuffer.size;
}

- (instancetype)copyWithAbsoluteBlockNumber:(long long)absoluteBlockNumber {
    LineBlock *theCopy = [self copyDeep:YES absoluteBlockNumber:absoluteBlockNumber];
    theCopy->_guid = [[NSUUID UUID] UUIDString];
    return theCopy;
}

- (void)copyMetadataTo:(LineBlock *)theCopy {
    // This is an opportunity for optimization, perhaps. We don't do COW for metadata but we could.
    theCopy->_metadataArray = [_metadataArray cowCopy];
    assert(theCopy->_metadataArray != nil);
}

- (LineBlock *)copyDeep:(BOOL)deep absoluteBlockNumber:(long long)absoluteBlockNumber {
    assert(_characterBuffer);

    self.hasBeenCopied = YES;

    LineBlock *theCopy;
    if (!deep) {
        theCopy = [[LineBlock alloc] initWithCharacterBuffer:_characterBuffer guid:_guid];
        theCopy->_absoluteBlockNumber = absoluteBlockNumber;
        [theCopy setBufferStartOffset:self.bufferStartOffset];
        theCopy->_firstEntry = _firstEntry;
        iTermAssignToConstPointer((void **)&theCopy->cumulative_line_lengths, (void *)cumulative_line_lengths);
        [self copyMetadataTo:theCopy];
        theCopy->cll_capacity = cll_capacity;
        theCopy->cll_entries = cll_entries;
        assert(theCopy->_metadataArray.numEntries == cll_entries);
        assert(theCopy->_metadataArray.first == _firstEntry);

        theCopy->is_partial = is_partial;
        theCopy->cached_numlines = cached_numlines;
        theCopy->cached_numlines_width = cached_numlines_width;
        // Don't copy the cache because doing so is expensive. I blame C++.
        theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;

        // Preserve these so delta encoding will continue to work when you encode a copy.
        theCopy->_generation = _generation;
        theCopy.hasBeenCopied = YES;

        return theCopy;
    }

    theCopy = [[LineBlock alloc] initWithCharacterBuffer:[_characterBuffer clone]
                                                    guid:_guid];
    theCopy->_absoluteBlockNumber = absoluteBlockNumber;
    [theCopy setBufferStartOffset:self.bufferStartOffset];
    theCopy->_firstEntry = _firstEntry;
    size_t cll_size = sizeof(int) * cll_capacity;
    iTermAssignToConstPointer((void **)&theCopy->cumulative_line_lengths, iTermMalloc(cll_size));

    memmove((void *)theCopy->cumulative_line_lengths,
            (const void *)cumulative_line_lengths,
            cll_size);
    [self copyMetadataTo:theCopy];
    [theCopy->_metadataArray willMutate];
    theCopy->cll_capacity = cll_capacity;
    theCopy->cll_entries = cll_entries;
    assert(theCopy->_metadataArray.first == _firstEntry);
    assert(theCopy->_metadataArray.numEntries == cll_entries);
    theCopy->is_partial = is_partial;
    theCopy->cached_numlines = cached_numlines;
    theCopy->cached_numlines_width = cached_numlines_width;
    theCopy->_generation = _generation;
    theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;
    theCopy.hasBeenCopied = YES;

    return theCopy;
}

- (BOOL)isEqual:(id)object {
    if (self == object){
        return YES;
    }
    LineBlock *other = [LineBlock castFrom:object];
    if (!other) {
        return NO;
    }
    if (self.bufferStartOffset != other.bufferStartOffset) {
        return NO;
    }
    if (_firstEntry != other->_firstEntry) {
        return NO;
    }
    if (_characterBuffer.size != other->_characterBuffer.size) {
        return NO;
    }
    if (cll_entries != other->cll_entries) {
        return NO;
    }
    if (is_partial != other->is_partial) {
        return NO;
    }
    for (int i = 0; i < cll_entries; i++) {
        if (cumulative_line_lengths[i] != other->cumulative_line_lengths[i]) {
            return NO;
        }
    }
    return [_characterBuffer deepIsEqual:other->_characterBuffer];
}

- (int)rawSpaceUsed {
    if (cll_entries == 0) {
        return 0;
    } else {
        return cumulative_line_lengths[cll_entries - 1];
    }
}

- (int)nonDroppedSpaceUsed {
    return self.rawSpaceUsed - _startOffset;
}

- (void)_appendCumulativeLineLength:(int)cumulativeLength
                           metadata:(iTermImmutableMetadata)lineMetadata
                       continuation:(screen_char_t)continuation
                               cert:(id<iTermLineBlockMutationCertificate>)cert {
    ITAssertWithMessage(_metadataArray.numEntries == cll_entries, @"_metadataArray.numEntries=%@ != cll_entries=%@", @(_metadataArray.numEntries), @(cll_entries));
    ITAssertWithMessage(_metadataArray.capacity >= cll_capacity, @"_metadataArray.capacity=%@ < cll_capacity=%@", @(_metadataArray.capacity), @(cll_capacity));
    if (cll_entries == cll_capacity) {
        cll_capacity = MAX(cll_entries + 1, cll_capacity * 2);
        [cert setCumulativeLineLengthsCapacity:cll_capacity];
        [_metadataArray increaseCapacityTo:cll_capacity];
        ITAssertWithMessage(_metadataArray.capacity >= cll_capacity,
                            @"_metadataArray.capacity=%@ < cll_capacity=%@", @(_metadataArray.capacity), @(cll_capacity));
        ITAssertWithMessage(_metadataArray.numEntries < _metadataArray.capacity,
                            @"_metadataArray.numEntries=%@ >= _metadataArray.capacity=%@",
                            @(_metadataArray.numEntries), @(_metadataArray.capacity));
    }
    ((int *)cumulative_line_lengths)[cll_entries] = cumulativeLength;
    [_metadataArray append:lineMetadata continuation:continuation];

    cll_entries += 1;
    assert(_metadataArray.numEntries == cll_entries);
}

- (void)appendToDebugString:(NSMutableString *)s {
    int i;
    int prev;
    if (_firstEntry > 0) {
        prev = cumulative_line_lengths[_firstEntry - 1];
    } else {
        prev = 0;
    }
    for (i = _firstEntry; i < cll_entries; ++i) {
        BOOL iscont = (i == cll_entries-1) && is_partial;
        NSString *string = ScreenCharArrayToStringDebug(_characterBuffer.pointer + _startOffset + prev - self.bufferStartOffset,
                                                        cumulative_line_lengths[i] - prev);
        [s appendFormat:@"%@%c\n",
         string,
         iscont ? '+' : '!'];
        prev = cumulative_line_lengths[i];
    }
}

- (NSString *)dumpString {
    return [self dumpStringWithDroppedChars:0];
}

- (NSString *)dumpStringWithDroppedChars:(long long)droppedChars {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    [strings addObject:[NSString stringWithFormat:@"numRawLines=%@", @([self numRawLines])]];

    int i;
    int rawOffset = 0;
    int prev;
    if (_firstEntry > 0) {
        prev = cumulative_line_lengths[_firstEntry - 1];
    } else {
        prev = 0;
    }
    for (i = _firstEntry; i < cll_entries; ++i) {
        BOOL iscont = (i == cll_entries-1) && is_partial;
        NSString *md = iTermMetadataShortDescription([_metadataArray metadataAtIndex:i]->lineMetadata,
                                                     cumulative_line_lengths[i] - prev);
        NSString *message = [NSString stringWithFormat:@"Line %d, length %d, offset from raw=%d, abs pos=%lld, continued=%s %@: %@\n",
                             i,
                             cumulative_line_lengths[i] - prev,
                             prev,
                             prev + rawOffset + droppedChars,
                             iscont?"yes":"no",
                             md,
                             [self debugStringForRawLine:i - _firstEntry]];
        [strings addObject:message];
        prev = cumulative_line_lengths[i];
    }
    return [strings componentsJoinedByString:@"\n"];
}

- (NSString *)debugStringForRawLine:(int)i {
    const screen_char_t *line = [self rawLine:i + _firstEntry];
    const int length = [self lengthOfRawLine:i + _firstEntry];
    const LineBlockMetadata *lbm = [_metadataArray metadataAtIndex:i + _firstEntry];
    screen_char_t continuation = lbm->continuation;
    if (i + _firstEntry == cll_entries - 1 && is_partial && continuation.code == EOL_HARD) {
        continuation.code = EOL_SOFT;
    }
    ScreenCharArray *sca = [[ScreenCharArray alloc] initWithLine:line
                                                          length:length
                                                        metadata:iTermMetadataMakeImmutable(lbm->lineMetadata)
                                                    continuation:lbm->continuation];
    return [sca stringValue];
}

- (void)dump:(int)rawOffset droppedChars:(long long)droppedChars toDebugLog:(BOOL)toDebugLog {
    if (toDebugLog) {
        DLog(@"numRawLines=%@", @([self numRawLines]));
    } else {
        NSLog(@"numRawLines=%@", @([self numRawLines]));
    }
    int i;
    int prev;
    if (_firstEntry > 0) {
        prev = cumulative_line_lengths[_firstEntry - 1];
    } else {
        prev = 0;
    }
    for (i = _firstEntry; i < cll_entries; ++i) {
        BOOL iscont = (i == cll_entries-1) && is_partial;
        NSString *md = iTermMetadataShortDescription([_metadataArray metadataAtIndex:i]->lineMetadata,
                                                     cumulative_line_lengths[i] - prev);
        NSString *message = [NSString stringWithFormat:@"Line %d, length %d, offset from raw=%d, abs pos=%lld, continued=%s %@: %@\n",
                             i,
                             cumulative_line_lengths[i] - prev,
                             prev,
                             prev + rawOffset + droppedChars,
                             iscont?"yes":"no",
                             md,
                             [self debugStringForRawLine:i]];
        if (toDebugLog) {
            DLog(@"%@", message);
        } else {
            NSLog(@"%@", message);
        }
        prev = cumulative_line_lengths[i];
    }
}

NS_INLINE int LineBlockNumberOfFullLinesFastPath(int length, int width) {
    // Need to use max(0) because otherwise we get -1 for length=0 width=1.
    return MAX(0, length - 1) / width;
}

- (int)numberOfFullLinesFromOffset:(int)offset
                            length:(int)length
                             width:(int)width {
    if (width <= 1 || !_mayHaveDoubleWidthCharacter) {
        return LineBlockNumberOfFullLinesFastPath(length, width);
    }

    auto key = iTermNumFullLinesCacheKey(offset, length, width);
    int result;
    auto insertResult = _numberOfFullLinesCache.insert(std::make_pair(key, -1));
    auto it = insertResult.first;
    auto wasInserted = insertResult.second;
    if (wasInserted) {
        result = [self calculateNumberOfFullLinesWithOffset:offset
                                                     length:length
                                                      width:width
                                                 mayHaveDWC:_mayHaveDoubleWidthCharacter];
        it->second = result;
    } else {
        result = it->second;
    }

    return result;
}

- (int)numberOfFullLinesFromBuffer:(const screen_char_t *)buffer
                            length:(int)length
                             width:(int)width {
    return [self numberOfFullLinesFromOffset:buffer - _characterBuffer.pointer
                                      length:length
                                       width:width];
}

static int iTermLineBlockNumberOfFullLinesImpl(const screen_char_t *buffer,
                                        int length,
                                        int width) {
    int fullLines = 0;
    for (int i = width; i < length; i += width) {
        if (ScreenCharIsDWC_RIGHT(buffer[i])) {
            --i;
        }
        ++fullLines;
    }
    return fullLines;
}

- (int)calculateNumberOfFullLinesWithOffset:(int)offset
                                     length:(int)length
                                      width:(int)width
                                 mayHaveDWC:(BOOL)mayHaveDWC {
    if (width <= 1 || !mayHaveDWC) {
        // Need to use max(0) because otherwise we get -1 for length=0 width=1.
        return LineBlockNumberOfFullLinesFastPath(length, width);
    }
    return iTermLineBlockNumberOfFullLinesImpl(_characterBuffer.pointer + offset, length, width);
}

- (NSInteger)sizeFromLine:(int)lineNum width:(int)width {
    int mutableLineNum = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&mutableLineNum];
    if (!location.found) {
        return 0;
    }
    // We found the raw line that includes the wrapped line we're searching for.
    // eat up *lineNum many width-sized wrapped lines from this start of the current full line
    iTermImmutableMetadata metadata = iTermMetadataMakeImmutable(iTermMetadataDefault());
    int length = 0;
    screen_char_t continuation = { 0 };
    int eol = 0;
    const int offset = [self _wrappedLineWithWrapWidth:width
                                              location:location
                                               lineNum:&mutableLineNum
                                            lineLength:&length
                                     includesEndOfLine:&eol
                                               yOffset:NULL
                                          continuation:&continuation
                                  isStartOfWrappedLine:NULL
                                              metadata:&metadata
                                              bidiInfo:NULL
                                            lineOffset:NULL];

    return [self rawSpaceUsed] - offset;
}


#ifdef TEST_LINEBUFFER_SANITY
- (void) checkAndResetCachedNumlines:(char *)methodName width:(int)width {
    int old_cached = cached_numlines;
    Boolean was_valid = cached_numlines_width != -1;
    cached_numlines_width = -1;
    int new_cached = [self getNumLinesWithWrapWidth:width];
    if (was_valid && old_cached != new_cached) {
        NSLog(@"%s: cached_numlines updated to %d, but should be %d!", methodName, old_cached, new_cached);
    }
}
#endif

- (BOOL)appendLine:(const screen_char_t*)buffer
            length:(int)length
           partial:(BOOL)partial
             width:(int)width
          metadata:(iTermImmutableMetadata)lineMetadata
      continuation:(screen_char_t)continuation {
    BOOL result;
    ModifyLineBlock(self, [buffer, length, partial, width, lineMetadata, continuation, &result, &self](id<iTermLineBlockMutationCertificate> cert) -> void {
        result = [self reallyAppendLine:buffer
                                 length:length
                                partial:partial
                                  width:width
                               metadata:lineMetadata
                           continuation:continuation
                                   cert:cert];
    });
    return result;
}

- (BOOL)reallyAppendLine:(const screen_char_t *)buffer
                  length:(int)length
                 partial:(BOOL)partial
                   width:(int)width
                metadata:(iTermImmutableMetadata)lineMetadata
            continuation:(screen_char_t)continuation
                    cert:(id<iTermLineBlockMutationCertificate>)cert {
    _numberOfFullLinesCache.clear();
    int space_used = [self rawSpaceUsed];
    int free_space = _characterBuffer.size - space_used - self.bufferStartOffset;
    if (length > free_space) {
        // Special case: if we're appending a partial line to a block that contains
        // only one partial line, resize the buffer instead of failing. This allows
        // incremental merge to work by keeping _appendOnlySinceLastCopy = YES.
        // Without this optimization, LineBuffer would pop the line and reappend it,
        // which sets _appendOnlySinceLastCopy = NO.
        if (partial && is_partial && cll_entries == _firstEntry + 1 && _firstEntry == 0 && self.bufferStartOffset == 0) {
            const int newCapacity = space_used + length;
            [self changeBufferSize:newCapacity cert:cert];
            // Recalculate free space after resize
            free_space = _characterBuffer.size - space_used - self.bufferStartOffset;
        } else {
            return NO;
        }
    }
    // A line block could hold up to maxint empty lines but that makes
    // -dictionary return a very large serialized state.
    static const int iTermLineBlockMaxLines = 10000;
    if (cll_entries >= iTermLineBlockMaxLines) {
        return NO;
    }
    memcpy(cert.mutableRawBuffer + space_used,
           buffer,
           sizeof(screen_char_t) * length);
    // There's an edge case here. In the else clause, the line buffer looks like this originally:
    //   |xxxx| EOL_SOFT
    // Then append an empty line with EOL_HARD. The desired result is
    //   |xxxx| EOL_SOFT
    //   ||     EOL_HARD
    // It's an edge case because even though the line buffer is in the "is_partial" state, we can't
    // just increment the last line's length.
    //
    // This can happen in practice if the now-empty line being appended formerly had some stuff
    // but that stuff was erased and the EOL_SOFT was left behind.
    BOOL didFindRTL = NO;
    if (is_partial && !(!partial && length == 0)) {
        // append to an existing line
        ITAssertWithMessage(cll_entries > 0, @"is_partial but has no entries");
        // If completing the line (hard EOL), invalidate incremental merge eligibility
        // since the copy will still think it's partial.
        if (!partial) {
            _appendOnlySinceLastCopy = NO;
        }
        // update the numlines cache with the new number of full lines that the updated line has.
        if (width != cached_numlines_width) {
            cached_numlines_width = -1;
        } else {
            int prev_cll = cll_entries > _firstEntry + 1 ? cumulative_line_lengths[cll_entries - 2] - self.bufferStartOffset : 0;
            int cll = cumulative_line_lengths[cll_entries - 1] - self.bufferStartOffset;
            int old_length = cll - prev_cll;
            int oldnum = [self numberOfFullLinesFromOffset:self.bufferStartOffset + prev_cll
                                                    length:old_length
                                                     width:width];
            int newnum = [self numberOfFullLinesFromOffset:self.bufferStartOffset + prev_cll
                                                    length:old_length + length
                                                     width:width];
            cached_numlines += newnum - oldnum;
        }

        int originalLength = cumulative_line_lengths[cll_entries - 1];
        if (cll_entries != _firstEntry + 1) {
            const int start = cumulative_line_lengths[cll_entries - 2] - self.bufferStartOffset;
            originalLength -= start;
        }
        cert.mutableCumulativeLineLengths[cll_entries - 1] += length;
        const iTermMetadata *amendedMetadata = [_metadataArray appendToLastLine:&lineMetadata
                                                                 originalLength:originalLength
                                                               additionalLength:length
                                                                   continuation:continuation];
        didFindRTL = amendedMetadata->rtlFound;
#ifdef TEST_LINEBUFFER_SANITY
        [self checkAndResetCachedNumlines:@"appendLine partial case" width:width];
#endif
    } else {
        // add a new line
        _appendOnlySinceLastCopy = NO;
        didFindRTL = lineMetadata.rtlFound;
        [self _appendCumulativeLineLength:(space_used + length)
                                 metadata:lineMetadata
                             continuation:continuation
                                     cert:cert];
        if (width != cached_numlines_width) {
            cached_numlines_width = -1;
        } else {
            const int marginalLines = [self numberOfFullLinesFromOffset:space_used
                                                                 length:length
                                                                  width:width] + 1;
            cached_numlines += marginalLines;
        }
#ifdef TEST_LINEBUFFER_SANITY
        [self checkAndResetCachedNumlines:"appendLine normal case" width:width];
#endif
    }
    is_partial = partial;
    if (didFindRTL) {
        [self didFindRTLInLine:cll_entries - 1 cert:cert];
    }
    iTermLineBlockDidChange(self, "append line");
    return YES;
}

- (void)didFindRTLInLine:(int)line cert:(id<iTermLineBlockMutationCertificate>)cert {
    const LineBlockMetadata *existing = [_metadataArray metadataAtIndex:line];
    if (!existing->lineMetadata.rtlFound) {
        [_metadataArray setRTLFound:YES atIndex:line];
    }
}

// Only used by tests
- (LineBlockMutableMetadata)internalMetadataForLine:(int)line {
    return iTermLineBlockMetadataProvideGetMutable([_metadataArray metadataProviderAtIndex:line]);
}

- (int)offsetOfStartOfLineIncludingOffset:(int)offset {
    int i = [self _findEntryBeforeOffset:offset];
    if (i < 0) {
        // _findEntryBeforeOffset returns -1 in two cases:
        // 1. offset < bufferStartOffset (before any valid data) - should return start of first line
        // 2. offset >= cumulative_line_lengths[cll_entries-1] (past end of buffer) - should return start of last line
        if (offset < self.bufferStartOffset) {
            // Case 1: offset is before valid data, return start of first line
            return self.bufferStartOffset;
        }
        // Case 2: offset is past end of buffer, return start of last line
        i = cll_entries - 1;
    }

    // Now i is the index of the line containing the offset.
    // Return the start of line i.
    // Note: cumulative_line_lengths[i] is the END of line i, so the START of line i is cumulative_line_lengths[i-1]
    // (or bufferStartOffset for the first entry).
    if (i <= _firstEntry || i <= 0) {
        // Either i == _firstEntry (the first valid line), or i < _firstEntry (shouldn't happen, but defensive).
        // In either case, return bufferStartOffset since we can't access cumulative_line_lengths before _firstEntry.
        return self.bufferStartOffset;
    }
    return cumulative_line_lengths[i - 1];
}

- (int)getPositionOfLine:(int *)lineNum
                     atX:(int)x
               withWidth:(int)width
                 yOffset:(int *)yOffsetPtr
                 extends:(BOOL *)extendsPtr {
    ITBetaAssert(*lineNum >= 0, @"Negative lines to getWrappedLineWithWrapWidth");
    VLog(@"getPositionOfLine:%@ atX:%@ withWidth:%@ yOffset:%@ extends:%@",
          @(*lineNum), @(x), @(width), @(*yOffsetPtr), @(*extendsPtr));

    int length;
    int eol;
    BOOL isStartOfWrappedLine = NO;

    VLog(@"getPositionOfLine: calling getWrappedLineWithWidth:%@ lineNum:%@ length:eol:yOffset:%@ continuation:NULL isStartOfWrappedLine: metadata:NULL",
          @(width), @(*lineNum), @(*yOffsetPtr));
    const screen_char_t *p = [self getWrappedLineWithWrapWidth:width
                                                       lineNum:lineNum
                                                    lineLength:&length
                                             includesEndOfLine:&eol
                                                       yOffset:yOffsetPtr
                                                  continuation:NULL
                                          isStartOfWrappedLine:&isStartOfWrappedLine
                                                      metadata:NULL];
    if (!p) {
        VLog(@"getPositionOfLine: getWrappedLineWithWidth returned nil");
        return -1;
    }
    VLog(@"getPositionOfLine: getWrappedLineWithWidth returned length=%@, eol=%@, yOffset=%@, isStartOfWrappedLine=%@",
          @(length), @(eol), yOffsetPtr ? [@(*yOffsetPtr) stringValue] : @"nil", @(isStartOfWrappedLine));

    int pos;
    // Note that this code is in a very delicate balance with -[LineBuffer coordinateForPosition:width:extendsRight:ok:], which interprets
    // *extendsPtr to pick an x coordate at the right margin.
    //
    // I chose to add the (x == length && *yOffsetPtr == 0) clause
    // because  otherwise there's no way to refer to the start of a blank line.
    // If you want it to extend you can always provide an x>0.
    VLog(@"getPositionOfLine: x=%@ length=%@ *yOffsetPtr=%@", @(x), @(length), @(*yOffsetPtr));
    if (x > length || (x == length && *yOffsetPtr == 0)) {
        VLog(@"getPositionOfLine: Set extends and advance pos to end of line");
        *extendsPtr = YES;
        pos = p - _characterBuffer.pointer + length;
    } else {
        VLog(@"getPositionOfLine: Clear extends and advance pos by x");
        *extendsPtr = NO;
        pos = p - _characterBuffer.pointer + x;
    }
    if (length > 0 && (!isStartOfWrappedLine || x > 0)) {
        VLog(@"getPositionOfLine: Set *yOffsetPtr <- 0");
        *yOffsetPtr = 0;
    } else if (length > 0 && isStartOfWrappedLine && x == 0) {
        VLog(@"getPositionOfLine: First char of a line");
        // First character of a line. For example, in this grid:
        //   abc.
        //   d...
        // The cell after c has position 3, as does the cell with d. The difference is that
        // d has a yOffset=1 and the null cell after c has yOffset=0.
        //
        // If you wanted the cell after c then x > 0.
        if (pos == 0 && *yOffsetPtr == 0) {
            // First cell of first line in block.
            VLog(@"getPositionOfLine: First cell of first line in block");
        } else {
            // First cell of second-or-later line in block.
            *yOffsetPtr += 1;
            VLog(@"getPositionOfLine: First cell of 2nd or later line, advance yOffset to %@", @(*yOffsetPtr));
        }
    }
    VLog(@"getPositionOfLine: getPositionOfLine returning %@, lineNum=%@ yOffset=%@ extends=%@",
          @(pos), @(*lineNum), @(*yOffsetPtr), @(*extendsPtr));
    return pos;
}

- (void)populateDoubleWidthCharacterCacheInMetadata:(LineBlockMutableMetadata)mutableMetadata
                                     startingOffset:(int)startingOffset
                                             length:(int)length
                                              width:(int)width {
    assert(gEnableDoubleWidthCharacterLineCache);
    mutableMetadata.metadata->doubleWidthCharacters =
        [[iTermDoubleWidthCharacterCache alloc] initWithCharacters:_characterBuffer.pointer + _startOffset + startingOffset
                                                            length:length
                                                             width:width];
}

// startingOffset is relative to bufferStart.
// return value must be at least equal to length.
- (int)offsetOfWrappedLineInBufferAtOffset:(int)startingOffset
                         wrappedLineNumber:(int)n  // lineNum
                              bufferLength:(int)length
                                     width:(int)width
                                  metadata:(iTermLineBlockMetadataProvider)metadataProvider {
    assert(gEnableDoubleWidthCharacterLineCache);
    ITBetaAssert(n >= 0, @"Negative lines to offsetOfWrappedLineInBuffer");
    const LineBlockMetadata *metadata = iTermLineBlockMetadataProviderGetImmutable(metadataProvider);
    if (_mayHaveDoubleWidthCharacter) {
        if (![metadata->doubleWidthCharacters validForWidth:width length:length]) {
            [self populateDoubleWidthCharacterCacheInMetadata:iTermLineBlockMetadataProvideGetMutable(metadataProvider)
                                               startingOffset:startingOffset
                                                       length:length
                                                        width:width];
        }
        int lines = 0;
        const int i = [metadata->doubleWidthCharacters offsetForWrappedLine:n totalLines:&lines];
        ITAssertWithMessage(i <= length, @"[2] i=%@ exceeds length=%@, n=%@, width=%@, lines=%@, bufferStartOffset=%@, startingOffset=%@, metadata_.width_for_number_of_wrapped_lines=%@, metadata->number_of_wrapped_lines=%@, numberOfFullLinesCache=%@, indexSet=%@, debugInfo=%@ clls=%@",
                            @(i),
                            @(length),
                            @(n),
                            @(width),
                            @(lines),
                            @(self.bufferStartOffset),
                            @(startingOffset),
                            @(metadata ? metadata->width_for_number_of_wrapped_lines : 0xdeadbeef),
                            @(metadata ? metadata->number_of_wrapped_lines : 0xdeadbeef),
                            [self dumpNumberOfFullLinesCache],
                            metadata->doubleWidthCharacters.indexSet,
                            _debugInfo ? _debugInfo() : @"n/a",
                            [self dumpCumulativeLineLengths]);
        return i;
    } else {
        ITAssertWithMessage(n * width <= length, @"[3] n=%@ * width=%@ < length=%@", @(n), @(width), @(length));
        return n * width;
    }
}

- (NSString *)dumpNumberOfFullLinesCache {
    NSMutableString *result = [NSMutableString string];

    for (const auto &entry : _numberOfFullLinesCache) {
        const iTermNumFullLinesCacheKey &key = entry.first;
        int value = entry.second;

        // Append the key and value to the result
        [result appendFormat:@"(%d, %d, %d) -> %d\n",
            key.offset, key.length, key.width, value];
    }
    return result;
}

- (NSString *)dumpCumulativeLineLengths {
    return [[[NSArray sequenceWithRange:NSMakeRange(_firstEntry, cll_entries - _firstEntry)] mapWithBlock:^id _Nullable(NSNumber * _Nonnull i) {
        return [NSString stringWithFormat:@"%@: %@", i, @(cumulative_line_lengths[i.integerValue])];
    }] componentsJoinedByString:@"\n"];
}

// TODO: Reduce use of this function in favor of the optimized method once I am confident it is correct.
int OffsetOfWrappedLine(const screen_char_t* p, int n, int length, int width, BOOL mayHaveDwc) {
    if (width > 1 && mayHaveDwc) {
        int lines = 0;
        int i = 0;
        while (lines < n) {
            // Advance i to the start of the next line
            i += width;
            ++lines;
            assert(i < length);
            if (ScreenCharIsDWC_RIGHT(p[i])) {
                // Oops, the line starts with the second half of a double-width
                // character. Wrap the last character of the previous line on to
                // this line.
                --i;
            }
        }
        return i;
    } else {
        return n * width;
    }
}

- (iTermImmutableMetadata)metadataForLineNumber:(int)lineNum width:(int)width {
    int mutableLineNum = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&mutableLineNum];
    int length = 0;
    int eof = 0;
    iTermMetadata metadata;
    int lineOffset = 0;
    [self _wrappedLineWithWrapWidth:width
                           location:location
                            lineNum:&mutableLineNum
                         lineLength:&length
                  includesEndOfLine:&eof
                            yOffset:NULL
                       continuation:NULL
               isStartOfWrappedLine:NULL
                           metadata:(iTermImmutableMetadata *)&metadata
                           bidiInfo:NULL
                         lineOffset:&lineOffset];
    iTermMetadata result;
    iTermMetadataInitCopyingSubrange(&result, (iTermImmutableMetadata *)&metadata, lineOffset, width);
    iTermMetadataAutorelease(result);
    return iTermMetadataMakeImmutable(result);
}

- (iTermBidiDisplayInfo *)bidiInfoForLineNumber:(int)lineNum width:(int)width {
    return [self _bidiInfoForLineNumber:lineNum width:width];
}

- (const screen_char_t *)getWrappedLineWithWrapWidth:(int)width
                                      lineNum:(int*)lineNum
                                   lineLength:(int*)lineLength
                            includesEndOfLine:(int*)includesEndOfLine
                                 continuation:(screen_char_t *)continuationPtr {
    return [self getWrappedLineWithWrapWidth:width
                                     lineNum:lineNum
                                  lineLength:lineLength
                           includesEndOfLine:includesEndOfLine
                                     yOffset:NULL
                                continuation:continuationPtr
                        isStartOfWrappedLine:NULL
                                    metadata:NULL];
}

- (int)cacheAwareOffsetOfWrappedLineInBuffer:(LineBlockLocation)location
                           wrappedLineNumber:(int)lineNum
                                       width:(int)width {
    if (gEnableDoubleWidthCharacterLineCache) {
        return [self offsetOfWrappedLineInBufferAtOffset:location.prev
                                       wrappedLineNumber:lineNum
                                            bufferLength:location.length
                                                   width:width
                                                metadata:[_metadataArray metadataProviderAtIndex:location.index]];
    }
    return OffsetOfWrappedLine(_characterBuffer.pointer + _startOffset + location.prev,
                               lineNum,
                               location.length,
                               width,
                               _mayHaveDoubleWidthCharacter);
}

- (int)_wrappedLineWithWrapWidth:(int)width
                        location:(LineBlockLocation)location
                         lineNum:(int*)lineNum
                      lineLength:(int*)lineLength
               includesEndOfLine:(int*)includesEndOfLine
                         yOffset:(int*)yOffsetPtr
                    continuation:(screen_char_t *)continuationPtr
            isStartOfWrappedLine:(BOOL *)isStartOfWrappedLine
                        metadata:(out iTermImmutableMetadata *)metadataPtr
                        bidiInfo:(out iTermBidiDisplayInfo **)bidiInfoPtr
                      lineOffset:(out int *)lineOffset {
    const screen_char_t *bufferStart = _characterBuffer.pointer + _startOffset;
    int offset = [self cacheAwareOffsetOfWrappedLineInBuffer:location
                                           wrappedLineNumber:*lineNum
                                                       width:width];

    *lineNum = 0;
    // offset: the relevant part of the raw line begins at this offset into it
    ITAssertWithMessage(location.length >= offset, @"length of %@ is less than offset %@", @(location.length), @(offset));
    *lineLength = location.length - offset;  // the length of the suffix of the raw line, beginning at the wrapped line we want
    // assert(*lineLength >= 0);
    if (*lineLength > width) {
        // return an infix of the full line
        const int i = location.prev + offset + width;
        ITAssertWithMessage(i < _characterBuffer.size && i >= 0,
                            @"i=%@ characterBuffer.size=%@ startOffset=%@ offset=%@ location=%@ width=%@",
                            @(i),
                            @(_characterBuffer.size),
                            @(_startOffset),
                            @(offset),
                            LineBlockLocationDescription(location),
                            @(width));
        const screen_char_t c = bufferStart[i];

        if (width > 1 && ScreenCharIsDWC_RIGHT(c)) {
            // Result would end with the first half of a double-width character
            *lineLength = width - 1;
            ITAssertWithMessage(*lineLength >= 0, @"1 Line length is negative at %@", @(*lineLength));
            // assert(*lineLength >= 0);
            *includesEndOfLine = EOL_DWC;
        } else {
            *lineLength = width;
            ITAssertWithMessage(*lineLength >= 0, @"2 Line length is negative at %@", @(*lineLength));
            // assert(*lineLength >= 0);
            *includesEndOfLine = EOL_SOFT;
        }
    } else {
        ITAssertWithMessage(*lineLength >= 0, @"3 Line length is negative at %@", @(*lineLength));
        // return a suffix of the full line
        if (location.index == cll_entries - 1 && is_partial) {
            // If this is the last line and it's partial then it doesn't have an end-of-line.
            *includesEndOfLine = EOL_SOFT;
        } else {
            *includesEndOfLine = EOL_HARD;
        }
    }
    if (yOffsetPtr) {
        // Set *yOffsetPtr to the number of consecutive empty lines just before the requested
        // line.
        *yOffsetPtr = location.numEmptyLines;
    }
    const LineBlockMetadata *md = [_metadataArray metadataAtIndex:location.index];
    if (continuationPtr) {
        *continuationPtr = md->continuation;
        continuationPtr->code = *includesEndOfLine;
    }
    if (isStartOfWrappedLine) {
        *isStartOfWrappedLine = (offset == 0);
    }
    if (metadataPtr) {
        iTermMetadataRetainAutorelease(md->lineMetadata);
        *metadataPtr = iTermMetadataMakeImmutable(md->lineMetadata);
    }
    if (bidiInfoPtr) {
        *bidiInfoPtr = [self subBidiInfo:md->bidi_display_info
                                   range:NSMakeRange(offset, width) width:width];
    }
    if (lineOffset) {
        *lineOffset = offset;
    }
    return location.prev + offset;
}

- (LineBlockLocation)locationOfRawLineForWidth:(int)width
                                       lineNum:(int *)lineNum {
    ITBetaAssert(*lineNum >= 0, @"Negative lines to getWrappedLineWithWrapWidth");
    int prev = 0;
    int numEmptyLines = 0;
    for (int i = _firstEntry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - self.bufferStartOffset;
        const int length = cll - prev;
        if (*lineNum > 0) {
            if (length == 0) {
                ++numEmptyLines;
            } else {
                numEmptyLines = 0;
            }
        } else if (length == 0 && cumulative_line_lengths[i] > self.bufferStartOffset) {
            // Callers use `prev`, the start of the *previous* wrapped line, plus the output *lineNum to find
            // where the wrapped line begins. When that line is of length 0 they will pick the end
            // of the last line rather than the start of the subsequent line. Increment numEmptyLines
            // to make it clear what we're indicating. This means that numEmptyLines modifies `.prev`
            // but *not* `.index`, which is super confusing :(
            // However, if this line was not preceded by a non-empty line, we don't want to make
            // this adjustment because that ambiguity is not possible.
            //
            // To illustrate:
            // 1. Given:
            //     abc
            //     (empty)
            //   Then the location for the start of line 1 is (prev=3,numEmptyLines=1,index=1,length=0)
            // 2. Given:
            //    (empty)
            //    (empty)
            //   Then the location for the start of line 1 is (prev=0,numEmptyLines=1,index=1,length=0)
            //
            // I don't think this is right. Probably a better way of referring to locations is needed.
            // For example if you have lines ["", "", "A", "", "BC"] then the locations of the last
            // two raw lines are the same (prev=1, numEmptyLines=1).
            ++numEmptyLines;
        }
        int spans;
        const BOOL useCache = gUseCachingNumberOfLines;
        if (useCache && _mayHaveDoubleWidthCharacter) {
            iTermLineBlockMetadataProvider provider = [_metadataArray metadataProviderAtIndex:i];
            const LineBlockMetadata *metadata = iTermLineBlockMetadataProviderGetImmutable(provider);
            if (metadata->width_for_number_of_wrapped_lines == width &&
                metadata->number_of_wrapped_lines > 0) {
                spans = metadata->number_of_wrapped_lines;
            } else {
                spans = [self numberOfFullLinesFromOffset:self.bufferStartOffset + prev
                                                   length:length
                                                    width:width];
                LineBlockMutableMetadata mutableMetadata = iTermLineBlockMetadataProvideGetMutable(provider);
                mutableMetadata.metadata->number_of_wrapped_lines = spans;
                mutableMetadata.metadata->width_for_number_of_wrapped_lines = width;
             }
        } else {
            spans = [self numberOfFullLinesFromOffset:self.bufferStartOffset + prev
                                               length:length
                                                width:width];
        }
        if (*lineNum > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            *lineNum -= consume;
            ITBetaAssert(*lineNum >= 0, @"Negative lines after consuming spans");
        } else {  // *lineNum <= spans
            // We found the raw line that includes the wrapped line we're searching for.
            // eat up *lineNum many width-sized wrapped lines from the start of the current full line
            return (LineBlockLocation){
                .found = YES,
                .prev = prev,
                .numEmptyLines = numEmptyLines,
                .index = i,
                .length = length
            };
        }
        prev = cll;
    }
    return (LineBlockLocation){
        .found = NO
    };
}

- (const screen_char_t *)getWrappedLineWithWrapWidth:(int)width
                                             lineNum:(int*)lineNum
                                          lineLength:(int*)lineLength
                                   includesEndOfLine:(int*)includesEndOfLine
                                             yOffset:(int*)yOffsetPtr
                                        continuation:(screen_char_t *)continuationPtr
                                isStartOfWrappedLine:(BOOL *)isStartOfWrappedLine
                                            metadata:(out iTermImmutableMetadata *)metadataPtr {
    ITBetaAssert(*lineNum >= 0, @"Negative lines to getWrappedLineWithWrapWidth");
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:lineNum];
    if (!location.found) {
        return NULL;
    }
    // We found the raw line that includes the wrapped line we're searching for.
    // eat up *lineNum many width-sized wrapped lines from this start of the current full line
    const int offset = [self _wrappedLineWithWrapWidth:width
                                              location:location
                                               lineNum:lineNum
                                            lineLength:lineLength
                                     includesEndOfLine:includesEndOfLine
                                               yOffset:yOffsetPtr
                                          continuation:continuationPtr
                                  isStartOfWrappedLine:isStartOfWrappedLine
                                              metadata:metadataPtr
                                              bidiInfo:NULL
                                            lineOffset:NULL];
    ITAssertWithMessage(*lineLength >= 0, @"Length is negative %@", @(*lineLength));

    return _characterBuffer.pointer + _startOffset + offset;
}

- (ScreenCharArray *)screenCharArrayForWrappedLineWithWrapWidth:(int)width
                                                        lineNum:(int)lineNum
                                                       paddedTo:(int)paddedSize
                                                 eligibleForDWC:(BOOL)eligibleForDWC {
    int mutableLineNum = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&mutableLineNum];
    if (!location.found) {
        return NULL;
    }
    // We found the raw line that includes the wrapped line we're searching for.
    // eat up *lineNum many width-sized wrapped lines from this start of the current full line
    iTermImmutableMetadata metadata = iTermMetadataMakeImmutable(iTermMetadataDefault());
    int length = 0;
    screen_char_t continuation = { 0 };
    int eol = 0;
    const screen_char_t *chunk = _characterBuffer.pointer + _startOffset;
    iTermBidiDisplayInfo *bidiInfo = nil;
    const int offset = [self _wrappedLineWithWrapWidth:width
                                              location:location
                                               lineNum:&mutableLineNum
                                            lineLength:&length
                                     includesEndOfLine:&eol
                                               yOffset:NULL
                                          continuation:&continuation
                                  isStartOfWrappedLine:NULL
                                              metadata:&metadata
                                              bidiInfo:&bidiInfo
                                            lineOffset:NULL];

    ;
    ScreenCharArray *sca = [[ScreenCharArray alloc] initWithLine:chunk + offset
                                                          length:length
                                                        metadata:metadata
                                                    continuation:continuation
                                                        bidiInfo:bidiInfo];
    return [sca paddedToLength:paddedSize eligibleForDWC:eligibleForDWC];
}

- (NSNumber *)rawLineNumberAtWrappedLineOffset:(int)lineNum width:(int)width {
    int temp = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&temp];
    if (!location.found) {
        return nil;
    }
    return @(location.index);
}

- (ScreenCharArray *)rawLineAtWrappedLineOffset:(int)lineNum width:(int)width {
    int temp = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&temp];
    if (!location.found) {
        return NULL;
    }
    const screen_char_t *buffer = _characterBuffer.pointer + _startOffset + location.prev;
    const int length = location.length;
    screen_char_t continuation = { 0 };
    if (is_partial && location.index + 1 == cll_entries) {
        continuation.code = EOL_SOFT;
    } else {
        continuation.code = EOL_HARD;
    }
    const LineBlockMetadata *md = [_metadataArray metadataAtIndex:location.index];

    return [[ScreenCharArray alloc] initWithLine:buffer
                                          length:length
                                        metadata:iTermMetadataMakeImmutable(md->lineMetadata)
                                    continuation:continuation];
}


- (iTermImmutableMetadata)metadataForRawLineAtWrappedLineOffset:(int)lineNum width:(int)width {
    int temp = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&temp];
    if (!location.found) {
        return iTermImmutableMetadataDefault();
    }
    return [_metadataArray immutableLineMetadataAtIndex:location.index];
}

- (int)getNumLinesWithWrapWidth:(int)width {
    ITBetaAssert(width > 0, @"Bogus value of width: %d", width);

    if (width == cached_numlines_width) {
        return cached_numlines;
    }

    int count = 0;
    int prev = 0;
    int i;
    // Count the number of wrapped lines in the block by computing the sum of the number
    // of wrapped lines each raw line would use.
    for (i = _firstEntry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - self.bufferStartOffset;
        int length = cll - prev;
        const int marginalLines = [self numberOfFullLinesFromOffset:self.bufferStartOffset + prev
                                                             length:length
                                                              width:width] + 1;
        count += marginalLines;
        prev = cll;
    }

    // Save the result so it doesn't have to be recalculated until some relatively rare operation
    // occurs that invalidates the cache.
    cached_numlines_width = width;
    cached_numlines = count;

    return count;
}

- (int)totallyUncachedNumLinesWithWrapWidth:(int)width {
    ITBetaAssert(width > 0, @"Bogus value of width: %d", width);

    int count = 0;
    int prev = 0;
    int i;
    // Count the number of wrapped lines in the block by computing the sum of the number
    // of wrapped lines each raw line would use.
    for (i = _firstEntry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - self.bufferStartOffset;
        int length = cll - prev;
        const int marginalLines = [self calculateNumberOfFullLinesWithOffset:self.bufferStartOffset + prev
                                                             length:length
                                                              width:width
                                                                  mayHaveDWC:_mayHaveDoubleWidthCharacter] + 1;
        count += marginalLines;
        prev = cll;
    }

    // Save the result so it doesn't have to be recalculated until some relatively rare operation
    // occurs that invalidates the cache.
    cached_numlines_width = width;
    cached_numlines = count;

    return count;
}

- (BOOL)hasCachedNumLinesForWidth:(int)width {
    return cached_numlines_width == width;
}

- (void)removeLastWrappedLines:(int)numberOfLinesToRemove
                         width:(int)width {
    for (int i = 0; i < numberOfLinesToRemove; i++) {
        int length = 0;
        const BOOL ok = [self popLastLineInto:nil
                                   withLength:&length
                                    upToWidth:width
                                     metadata:nil
                                 continuation:nil];
        if (!ok) {
            return;
        }
    }
}

- (void)removeLastRawLine {
    _appendOnlySinceLastCopy = NO;
    if (cll_entries == _firstEntry) {
        return;
    }

    [_metadataArray willMutate];

    cll_entries -= 1;
    [_metadataArray removeLast];

    is_partial = NO;
    if (cll_entries == _firstEntry) {
        // Popped the last line. Reset everything.
        [self setBufferStartOffset:0];
        _firstEntry = 0;
        cll_entries = 0;
        [_metadataArray reset];
    }
    assert(_metadataArray.first == _firstEntry);
    assert(_metadataArray.numEntries == cll_entries);

    cached_numlines_width = -1;
    iTermLineBlockDidChange(self, "remove last raw line");
}

- (BOOL)popLastLineInto:(screen_char_t const **)ptr
             withLength:(int *)length
              upToWidth:(int)width
               metadata:(out iTermImmutableMetadata *)metadataPtr
           continuation:(screen_char_t *)continuationPtr {
    BOOL result;
    ModifyLineBlock(self, [self, &result, ptr, length, width, metadataPtr, continuationPtr](id<iTermLineBlockMutationCertificate> cert) -> void {
        result = [self reallyPopLastLineInto:ptr
                                  withLength:length
                                   upToWidth:width
                                    metadata:metadataPtr
                                continuation:continuationPtr
                                        cert:cert];
    });
    return result;
}

- (BOOL)reallyPopLastLineInto:(screen_char_t const **)ptr
                   withLength:(int *)length
                    upToWidth:(int)width
                     metadata:(out iTermImmutableMetadata *)metadataPtr
                 continuation:(screen_char_t *)continuationPtr
                         cert:(id<iTermLineBlockMutationCertificate>)cert {
    _appendOnlySinceLastCopy = NO;
    if (cll_entries == _firstEntry) {
        // There is no last line to pop.
        return NO;
    }
    _numberOfFullLinesCache.clear();
    int start;
    if (cll_entries == _firstEntry + 1) {
        start = 0;
    } else {
        start = cumulative_line_lengths[cll_entries - 2] - self.bufferStartOffset;
    }
    if (continuationPtr) {
        *continuationPtr = [_metadataArray lastContinuation];
    }

    const int end = cumulative_line_lengths[cll_entries - 1] - self.bufferStartOffset;
    const int available_len = end - start;
    if (available_len > width) {
        // The last raw line is longer than width. So get the last part of it after wrapping.
        // If the width is four and the last line is "0123456789" then return "89". It would
        // wrap as: 0123/4567/89. If there are double-width characters, this ensures they are
        // not split across lines when computing the wrapping.
        const int numLines = [self numberOfFullLinesFromOffset:self.bufferStartOffset + start
                                                        length:available_len
                                                         width:width];
        int offset_from_start = OffsetOfWrappedLine(_characterBuffer.pointer + _startOffset + start,
                                                    numLines,
                                                    available_len,
                                                    width,
                                                    _mayHaveDoubleWidthCharacter);
        *length = available_len - offset_from_start;
        if (ptr) {
            *ptr = _characterBuffer.pointer + _startOffset + start + offset_from_start;
        }
        cert.mutableCumulativeLineLengths[cll_entries - 1] -= *length;
        [_metadataArray eraseLastLineCache];
        id<iTermExternalAttributeIndexReading> attrs = [_metadataArray lastExternalAttributeIndex];
        const int split_index = available_len - *length;
        [_metadataArray setLastExternalAttributeIndex:[attrs subAttributesFromIndex:split_index]];
        if (metadataPtr) {
            *metadataPtr = [_metadataArray immutableLineMetadataAtIndex:cll_entries - 1];
        }

        is_partial = YES;
    } else {
        // The last raw line is not longer than width. Return the whole thing.
        *length = available_len;
        if (ptr) {
            *ptr = _characterBuffer.pointer + _startOffset + start;
        }
        if (metadataPtr) {
            *metadataPtr = [_metadataArray immutableLineMetadataAtIndex:cll_entries - 1];
        }
        [_metadataArray removeLast];
        --cll_entries;
        assert(_metadataArray.numEntries == cll_entries);
        is_partial = NO;
    }

    if (cll_entries == _firstEntry) {
        // Popped the last line. Reset everything.
        [self setBufferStartOffset:0];
        _firstEntry = 0;
        cll_entries = 0;
        [_metadataArray reset];
        assert(_metadataArray.first == _firstEntry);
        assert(_metadataArray.numEntries == cll_entries);
    }
    // refresh cache
    cached_numlines_width = -1;
    iTermLineBlockDidChange(self, "pop");
    return YES;
}

- (BOOL)isEmpty {
    return cll_entries == _firstEntry;
}

- (BOOL)allLinesAreEmpty {
    if (self.isEmpty) {
        return YES;
    }
    return (cumulative_line_lengths[cll_entries - 1] == self.bufferStartOffset);
}

- (int)firstEntry {
    return _firstEntry;
}

- (int)numRawLines {
    return cll_entries - _firstEntry;
}

- (int)numEntries {
    return cll_entries;
}

- (int)startOffset {
    return self.bufferStartOffset;
}

- (int)lengthOfLastLine {
    if ([self numRawLines] == 0) {
        return 0;
    }
    const int index = cll_entries - 1;
    return [self lengthOfRawLine:index];
}

- (int)numberOfWrappedLinesForLastRawLineWrappedToWidth:(int)width {
    int temp = [self getNumLinesWithWrapWidth:width];
    if (temp == 0) {
        return 0;
    }
    temp -= 1;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&temp];
    if (!location.found) {
        return 0;
    }
    int x;
    int y;
    if (![self convertPosition:location.prev withWidth:width wrapOnEOL:YES toX:&x toY:&y]) {
        return 0;
    }

    const int numLines = [self getNumLinesWithWrapWidth:width];
    return (numLines - y);
}

- (int)lengthOfLastWrappedLineForWidth:(int)width {
    if (cll_entries == 0) {
        return 0;
    }
    const int length = [self lengthOfLastLine];
    if (length == 0) {
        return 0;
    }
    int temp = [self getNumLinesWithWrapWidth:width];
    if (temp == 0) {
        return 0;
    }
    temp -= 1;
    const LineBlockLocation location = {
        // Is this structure valid?
        .found = YES,

        // Offset of the start of the wrapped line from bufferStart.
        .prev = cumulative_line_lengths[cll_entries - 1] - self.startOffset,

        // How many empty lines to skip at prev.
        .numEmptyLines = 0,

        // Raw line number.
        .index = cll_entries - 1,

        // Length of the raw line.
        .length = length
    };
    int x;
    int y;
    if (![self convertPosition:location.prev withWidth:width wrapOnEOL:NO toX:&x toY:&y]) {
        return 0;
    }
    return x;
}

- (ScreenCharArray *)lastRawLine {
    if (cll_entries <= _firstEntry) {
        return nil;
    }
    const LineBlockMetadata *md = [_metadataArray metadataAtIndex:cll_entries - 1];

    return [[ScreenCharArray alloc] initWithLine:[self rawLine:cll_entries - 1]
                                          length:[self lengthOfLastLine]
                                        metadata:iTermMetadataMakeImmutable(md->lineMetadata)
                                    continuation:md->continuation];
}

- (int)lengthOfRawLine:(int)linenum {
    if (cll_entries == 0) {
        return 0;
    }
    ITAssertWithMessage(linenum < cll_entries && linenum >= _firstEntry, @"Out of bounds");

    int offset = 0;
    if (linenum == _firstEntry) {
        offset = _startOffset;
    } else {
        offset = cumulative_line_lengths[linenum - 1];
    }
    return cumulative_line_lengths[linenum] - offset;
}

- (int)offsetOfRawLine:(int)linenum {
    if (linenum == _firstEntry) {
        return self.bufferStartOffset;
    } else {
        return cumulative_line_lengths[linenum - 1];
    }
}

- (ScreenCharArray *)screenCharArrayForRawLine:(int)linenum {
    const LineBlockMetadata *md = [_metadataArray metadataAtIndex:linenum];
    return [[ScreenCharArray alloc] initWithLine:[self rawLine:linenum]
                                          length:[self lengthOfRawLine:linenum]
                                        metadata:iTermMetadataMakeImmutable(md->lineMetadata)
                                    continuation:md->continuation];
}

- (const screen_char_t*)rawLine:(int)linenum {
    int start;
    if (linenum == _firstEntry) {
        start = self.bufferStartOffset;
    } else {
        start = cumulative_line_lengths[linenum - 1];
    }
    return _characterBuffer.pointer + start;
}

- (BOOL)shouldOptimizeOutBufferSizeChangeTo:(int)desiredCapacity
                               assumeLocked:(BOOL)assumeLocked {
    if (self.hasBeenCopied && !assumeLocked) {
        return NO;
    }
    const int existing = _characterBuffer.size;
    if (desiredCapacity > existing) {
        return NO;
    }
    return (existing - desiredCapacity) > 100;
}

- (void)changeBufferSize:(int)capacity {
    if ([self shouldOptimizeOutBufferSizeChangeTo:capacity assumeLocked:NO]) {
        return;
    }
    ModifyLineBlock(self, [&self, capacity](id<iTermLineBlockMutationCertificate> cert) -> void {
        if ([self shouldOptimizeOutBufferSizeChangeTo:capacity assumeLocked:YES]) {
            return;
        }
        [self changeBufferSize:capacity cert:cert];
    });
}

- (void)changeBufferSize:(int)capacity cert:(id<iTermLineBlockMutationCertificate>)cert {
    ITAssertWithMessage(capacity >= [self rawSpaceUsed], @"Truncating used space");
    capacity = MAX(1, capacity);
    [cert setRawBufferCapacity:capacity];
    cached_numlines_width = -1;
}

- (BOOL)hasPartial {
    return is_partial;
}

- (void)setPartial:(BOOL)partial {
    if (partial == is_partial) {
        return;
    }
    _appendOnlySinceLastCopy = NO;
    is_partial = partial;
    iTermLineBlockDidChange(self, "set partial");
}

- (void)shrinkToFit {
    if ([self shouldOptimizeOutBufferSizeChangeTo:self.rawSpaceUsed assumeLocked:NO]) {
        return;
    }
    ModifyLineBlock(self, [self](id<iTermLineBlockMutationCertificate> cert) -> void {
        // If the difference is tiny, don't bother.
        if ([self shouldOptimizeOutBufferSizeChangeTo:self.rawSpaceUsed assumeLocked:YES]) {
            return;
        }
        [self changeBufferSize:[self rawSpaceUsed] cert:cert];
    });
}

- (int)dropLines:(int)orig_n withWidth:(int)width chars:(int *)charsDropped {
    _appendOnlySinceLastCopy = NO;
    // Note that there's no mutation certificate because we aren't touching the character buffer.
    [_metadataArray willMutate];

    int n = orig_n;
    int prev = 0;
    int length;
    int i;
    *charsDropped = 0;
    int initialOffset = self.bufferStartOffset;

    _numberOfFullLinesCache.clear();

    for (i = _firstEntry; i < cll_entries; ++i) {
        const int bufferStartOffset = self.bufferStartOffset;
        int cll = cumulative_line_lengths[i] - bufferStartOffset;
        length = cll - prev;
        // Get the number of full-length wrapped lines in this raw line. If there
        // were only single-width characters the formula would be:
        //     (length - 1) / width;
        int spans = [self numberOfFullLinesFromOffset:bufferStartOffset + prev
                                               length:length
                                                width:width];
        if (n > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            n -= consume;
        } else {  // n <= spans
            // We found the raw line that includes the wrapped line we're searching for.
            // Set offset to the offset into the raw line where the nth wrapped
            // line begins.
            int offset = OffsetOfWrappedLine(_characterBuffer.pointer + _startOffset + prev,
                                             n,
                                             length,
                                             width,
                                             _mayHaveDoubleWidthCharacter);
            if (width != cached_numlines_width) {
                cached_numlines_width = -1;
            } else {
                cached_numlines -= orig_n;
            }
            [self setBufferStartOffset:bufferStartOffset + prev + offset];

            _firstEntry = i;
            [_metadataArray removeFirst:_firstEntry - _metadataArray.first];
            assert(_metadataArray.first == _firstEntry);
            [_metadataArray eraseFirstLineCache];

            *charsDropped = self.bufferStartOffset - initialOffset;

#ifdef TEST_LINEBUFFER_SANITY
            [self checkAndResetCachedNumlines:"dropLines" width:width];
#endif
            iTermLineBlockDidChange(self, "drop");
            return orig_n;
        }
        prev = cll;
    }

    // Consumed the whole buffer.
    *charsDropped = [self rawSpaceUsed];
    [_metadataArray reset];
    cached_numlines_width = -1;
    cll_entries = 0;
    is_partial = NO;
    [self setBufferStartOffset:0];
    _firstEntry = 0;
    iTermLineBlockDidChange(self, "drop lines");
    assert(_metadataArray.first == _firstEntry);
    assert(_metadataArray.numEntries == cll_entries);
    return orig_n - n;
}

- (void)reloadBidiInfo {
    [_metadataArray willMutate];
    [self reallyReloadBidiInfo];
}

- (void)setBidiForLastRawLine:(iTermBidiDisplayInfo *)bidi {
    assert(cll_entries > 0);
    [_metadataArray setBidiInfo:bidi atLine:cll_entries - 1 rtlFound:bidi != nil];
}

- (void)eraseRTLStatusInAllCharacters {
    if (cll_entries == 0) {
        return;
    }
    screen_char_t *c = _characterBuffer.mutablePointer;
    for (int i = self.bufferStartOffset; i < cumulative_line_lengths[cll_entries - 1]; i++) {
        c[i].rtlStatus = RTLStatusUnknown;
    }
}

// self and other will have a common ancestor by following `owner`. It may be like:
//
//                 [mutation thread instance] <-owner- [main thread instance] <-owner- [search instance]
- (void)dropMirroringProgenitor:(LineBlock *)other {
    assert(_progenitor == other);
    assert(cll_capacity <= other->cll_capacity);
    assert(_metadataArray.first == _firstEntry);

    if (self.bufferStartOffset == other.bufferStartOffset &&
        _firstEntry == other->_firstEntry) {
        DLog(@"No change");
        return;
    }

    [_metadataArray willMutate];

    DLog(@"start_offset %@ -> %@", @(self.bufferStartOffset), @(other.bufferStartOffset));
    [self setBufferStartOffset:other.bufferStartOffset];
    cached_numlines_width = -1;

    while (_firstEntry < other->_firstEntry && _firstEntry < cll_capacity) {
        DLog(@"Drop entry");
        [_metadataArray removeFirst];
        _firstEntry += 1;
        assert(_metadataArray.first == _firstEntry);
    }
    if (_firstEntry < cll_entries) {
        // Force number_of_wrapped_lines to be recomputed for the first line in this block since it
        // may have experienced a partial drop (the first raw line was shorted by removing some from
        // its start).
        [_metadataArray eraseFirstLineCache];
    }
#ifdef TEST_LINEBUFFER_SANITY
    [self checkAndResetCachedNumlines:"dropLines" width:width];
#endif
    iTermLineBlockDidChange(self, "drop mirroring progenitor");
}

- (BOOL)isSynchronizedWithProgenitor {
    if (!_progenitor) {
        return NO;
    }
    if (_progenitor.invalidated) {
        return NO;
    }
    // Mutating an object nils its owner and points its clients at a different or nil owner.
    return _progenitor == _owner;
}

- (BOOL)appendOnlySinceLastCopy {
    return _appendOnlySinceLastCopy;
}

- (BOOL)canIncrementalMergeFromProgenitor {
    if (!_progenitor || _progenitor.invalidated) {
        return NO;
    }
    // If copy has diverged (was mutated), we can't do incremental merge
    // because its buffer no longer matches the sync-time state.
    if (_hasDiverged) {
        return NO;
    }
    if (!_progenitor->_appendOnlySinceLastCopy) {
        return NO;
    }
    // Both must have exactly one raw line, both partial, no drops
    if (cll_entries != _firstEntry + 1 ||
        _progenitor->cll_entries != _progenitor->_firstEntry + 1) {
        return NO;
    }
    if (!is_partial || !_progenitor->is_partial) {
        return NO;
    }
    if (_firstEntry != 0 || self.bufferStartOffset != 0) {
        return NO;
    }
    // Progenitor must have grown
    const int progenitorLen = _progenitor->cumulative_line_lengths[_progenitor->_firstEntry] - _progenitor.bufferStartOffset;
    const int myLen = cumulative_line_lengths[_firstEntry] - self.bufferStartOffset;
    return progenitorLen > myLen;
}

- (void)incrementalMergeFromProgenitor {
    std::lock_guard<std::recursive_mutex> lock(gLineBlockMutex);

    LineBlock *progenitor = _progenitor;
    const int progenitorLen = progenitor->cumulative_line_lengths[progenitor->_firstEntry] - progenitor.bufferStartOffset;
    const int myLen = cumulative_line_lengths[_firstEntry] - self.bufferStartOffset;
    const int appendedLen = progenitorLen - myLen;

    // Get private buffers (clones OLD shared state = data at sync point)
    id<iTermLineBlockMutationCertificate> cert = [self validMutationCertificate];

    // Resize if needed
    if (_characterBuffer.size < progenitorLen) {
        [cert setRawBufferCapacity:progenitorLen];
    }

    // Copy only appended characters
    memcpy(cert.mutableRawBuffer + myLen,
           progenitor->_characterBuffer.pointer + progenitor.bufferStartOffset + myLen,
           appendedLen * sizeof(screen_char_t));

    // Update cumulative line length
    cert.mutableCumulativeLineLengths[_firstEntry] = progenitorLen;

    // Sync metadata from progenitor
    // We need to extract the metadata for just the appended portion.
    // The progenitor's metadata covers the entire line; we need to sync:
    // - timestamp (use progenitor's current timestamp)
    // - rtlFound (OR with progenitor's flag)
    // - externalAttributes (extract slice for appended range)
    // - continuation (use progenitor's current continuation)
    [_metadataArray willMutate];
    const LineBlockMetadata *progenitorMeta = [progenitor->_metadataArray metadataAtIndex:progenitor->_firstEntry];

    // Create metadata for the appended portion by extracting from progenitor
    iTermImmutableMetadata progenitorLineMeta = iTermMetadataMakeImmutable(progenitorMeta->lineMetadata);

    // Extract external attributes for just the appended range [myLen, progenitorLen)
    iTermMetadata appendedMeta;
    iTermMetadataInitCopyingSubrange(&appendedMeta, &progenitorLineMeta, myLen, appendedLen);
    iTermImmutableMetadata immutableAppendedMeta = iTermMetadataMakeImmutable(appendedMeta);

    // Merge metadata using appendToLastLine which handles:
    // - timestamp update
    // - rtlFound OR
    // - external attributes concatenation with position adjustment
    // - continuation update
    // - Cache invalidation (number_of_wrapped_lines=0, DWC cache=nil, bidi_info=nil)
    [_metadataArray appendToLastLine:&immutableAppendedMeta
                      originalLength:myLen
                    additionalLength:appendedLen
                        continuation:progenitorMeta->continuation];

    iTermMetadataRelease(appendedMeta);

    // Invalidate caches that appendToLastLine doesn't handle
    _numberOfFullLinesCache.clear();
    cached_numlines_width = -1;  // Force recomputation of wrapped line count

    // Sync DWC flag (sticky - once set, stays set)
    if (progenitor->_mayHaveDoubleWidthCharacter) {
        _mayHaveDoubleWidthCharacter = YES;
    }

    iTermLineBlockDidChange(self, "incremental merge");
}

- (int)_lineRawOffset:(int) anIndex {
    if (anIndex == _firstEntry) {
        return self.bufferStartOffset;
    } else {
        return cumulative_line_lengths[anIndex - 1];
    }
}

// Returns the index into rawline that a result was found.
// Fills in *resultLength with the number of screen_char_t's the result spans.
// Fills in *rangeOut with the range of haystack/charHaystack where the result was found.

#if DEBUG_SEARCH
- (NSString *)prettyRawLine:(const screen_char_t *)line length:(int)length {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < length; i++) {
        unichar c = line[i].code;
        if (line[i].complexChar) {
            c = 'C';
        } else if (c < 32) {
            c = '^';
        } else if (c == ' ') {
            c = '_';
        } else if (c > 127) {
            c = 'H';
        }
        [s appendCharacter:c];
    }
    return s;
}

- (NSString *)prettyDeltas:(const int *)deltas length:(int)length {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < length; i++) {
        [a addObject:[@(deltas[i]) stringValue]];
    }
    return [a componentsJoinedByString:@" "];
}
#endif

- (NSString *)stringFromOffset:(int)offset
                        length:(int)length
                  backingStore:(unichar **)backingStorePtr
                        deltas:(int **)deltasPtr {
    return ScreenCharArrayToString(_characterBuffer.pointer + offset,
                                   0,
                                   length,
                                   backingStorePtr,
                                   deltasPtr);
}

- (void)_findInRawLine:(int)entry
                needle:(NSString*)needle
               options:(FindOptions)options
                  mode:(iTermFindMode)mode
                  skip:(int)skip
                length:(int)raw_line_length
       multipleResults:(BOOL)multipleResults
               results:(NSMutableArray *)results {
    if (skip > raw_line_length) {
        skip = raw_line_length;
    }
    if (skip < 0) {
        skip = 0;
    }

    unichar *charHaystack;
    int *deltas;
    const int rawOffset = [self _lineRawOffset:entry];
    NSString *haystack = [self stringFromOffset:rawOffset
                                         length:raw_line_length
                                   backingStore:&charHaystack
                                         deltas:&deltas];

#ifdef DEBUG_SEARCH
    SearchLog(@"Searching rawline %@", [self prettyRawLine:_characterBuffer.pointer + rawOffset
                                                    length:raw_line_length]);
    SearchLog(@"Deltas: %@", [self prettyDeltas:deltas length:haystack.length]);
#endif
    CoreSearchRequest request = {
        .needle = needle,
        .options = options,
        .mode = mode,
        .haystack = haystack,
        .deltas = deltas
    };
    NSArray<ResultRange *> *marginalResults = CoreSearch(&request);
    if (options & FindOptBackwards) {
        marginalResults = [marginalResults filteredArrayUsingBlock:^BOOL(ResultRange *rr) {
            return rr.position <= skip;
        }];
    } else {
        marginalResults = [marginalResults filteredArrayUsingBlock:^BOOL(ResultRange *rr) {
            return rr.position >= skip;
        }];
    }
    if (marginalResults.count) {
        if ((options & FindOneResultPerRawLine) || ((options & FindMultipleResults) == 0)) {
            [results addObject:marginalResults.firstObject];
        } else {
            [results addObjectsFromArray:marginalResults];
        }
    }

    free(deltas);
    free(charHaystack);
}

- (int) _lineLength:(int)anIndex {
    int prev;
    if (anIndex == _firstEntry) {
        prev = self.bufferStartOffset;
    } else {
        prev = cumulative_line_lengths[anIndex - 1];
    }
    return cumulative_line_lengths[anIndex] - prev;
}

- (int) _findEntryBeforeOffset:(int)offset {
    if (offset < self.bufferStartOffset) {
        return -1;
    }

    int i;
    for (i = _firstEntry; i < cll_entries; ++i) {
        if (cumulative_line_lengths[i] > offset) {
            return i;
        }
    }
    return -1;
}

// Search for a multi-line pattern starting at the given entry.
// Returns a state object indicating the result:
// - If state.result is non-nil: a complete match was found.
// - If state.needsContinuation is YES: ran out of lines, continue on next block.
// - Otherwise: no match was found starting at this entry.
//
// To resume a search on a subsequent block, pass in the returned state as priorState.
// For a fresh search, pass nil for priorState.
- (LineBlockMultiLineSearchState *)_searchMultiLineFromEntry:(int)entry
                                                  splitLines:(NSArray<NSString *> *)splitLines
                                                     options:(FindOptions)options
                                                        mode:(iTermFindMode)mode
                                                        skip:(int)skipped
                                             multipleResults:(BOOL)multipleResults
                                                  priorState:(LineBlockMultiLineSearchState *)priorState {
    static const int MAX_SEARCHABLE_LINE_LENGTH = 30000000;
    const BOOL backward = (options & FindOptBackwards) != 0;
    DLog(@"Searching for multi-line pattern starting at entry %d, backward=%d, priorState=%@", entry, backward, priorState);

    // Initialize from prior state if resuming, otherwise start fresh.
    NSInteger startIndex = priorState ? priorState.queryLineIndex : 0;
    MutableResultRange *multiLineRange = priorState ? priorState.partialResult : nil;

    // For backward search, we accumulate length first and set position at the end.
    // This tracks accumulated length until we find the first query line.
    int accumulatedLength = multiLineRange ? multiLineRange.length : 0;

    // Match each line in the query in turn.
    for (NSInteger i = startIndex; i < (NSInteger)splitLines.count; i++) {
        // Calculate raw line index and query line index based on direction.
        // For a fresh search (startIndex=0):
        //   Forward: iterate through query lines 0, 1, 2, ... matching raw lines entry, entry+1, entry+2, ...
        //   Backward: iterate through query lines N-1, N-2, ... matching raw lines entry, entry-1, entry-2, ...
        // For a continuation (startIndex>0), we offset by startIndex so that:
        //   rawLineIndex starts at entry when i=startIndex
        const int rawLineIndex = backward ? (entry - (int)(i - startIndex)) : (entry + (int)(i - startIndex));
        const NSInteger queryLineIndex = backward ? ((NSInteger)splitLines.count - 1 - i) : i;

        // Check if we've run out of lines in this block.
        if (backward) {
            if (rawLineIndex < _firstEntry) {
                DLog(@"Ran out of lines in block at query index %@, need to continue on previous block", @(i));
                MutableResultRange *partial = [[MutableResultRange alloc] initWithPosition:0 length:accumulatedLength];
                return [LineBlockMultiLineSearchState stateNeedingContinuationAtIndex:i
                                                                        partialResult:partial];
            }
        } else {
            if (rawLineIndex >= cll_entries) {
                DLog(@"Ran out of lines in block at query index %@, need to continue on next block", @(i));
                return [LineBlockMultiLineSearchState stateNeedingContinuationAtIndex:i
                                                                        partialResult:multiLineRange];
            }
        }

        NSString *queryLine = splitLines[queryLineIndex];
        NSMutableArray* lineResults = [NSMutableArray arrayWithCapacity:1];
        if (queryLine.length == 0) {
            DLog(@"Every line matches an empty string.");
            [lineResults addObject:[[ResultRange alloc] initWithPosition:0 length:0]];
        } else {
            // Only apply the skip restriction to the first entry of a fresh search.
            // For subsequent entries in a multi-line match (and for all entries in a
            // continuation from a prior block), search the entire line. The skip value
            // constrains _findInRawLine via position filtering (backward: position <= skip,
            // forward: position >= skip), so we need to use an unrestricted value for
            // non-initial entries. Without this, a continuation with skip=0 would filter
            // out matches at non-zero positions in backward search.
            const int lineSkip = (i == startIndex && priorState == nil) ? skipped : (backward ? [self _lineLength:rawLineIndex] : 0);
            DLog(@"Search raw line %d for query line %@ ('%@'). skip=%d", rawLineIndex, @(queryLineIndex), queryLine, lineSkip);
            [self _findInRawLine:rawLineIndex
                          needle:queryLine
                         options:options
                            mode:mode
                            skip:lineSkip
                          length:MIN(MAX_SEARCHABLE_LINE_LENGTH, [self _lineLength:rawLineIndex])
                 multipleResults:multipleResults
                         results:lineResults];
        }
        if (lineResults.count == 0) {
            DLog(@"No matches");
            return nil;
        }

        // Determine match criteria based on query line position (not iteration order).
        // First query line (idx=0): must extend to end of line
        // Last query line (idx=N-1): must start at position 0
        // Middle query lines: must start at 0 AND extend to end
        const BOOL isFirstQueryLine = (queryLineIndex == 0);
        const BOOL isLastQueryLine = (queryLineIndex == (NSInteger)splitLines.count - 1);
        const BOOL mustStartAtZero = !isFirstQueryLine;  // middle or last
        const BOOL mustExtendToEnd = !isLastQueryLine;   // first or middle

        ResultRange *range = nil;
        const int lineLength = [self lengthOfRawLine:rawLineIndex];

        if (mustStartAtZero) {
            // Pick a result that starts at 0 and has the greatest length.
            range = [[lineResults filteredArrayUsingBlock:^BOOL(ResultRange *r) {
                return r.position == 0;
            }]
                     maxWithBlock:^NSComparisonResult(ResultRange *lhs, ResultRange *rhs) {
                return [@(lhs.length) compare:@(rhs.length)];
            }];
        } else {
            // For the first line of the query:
            // If there were multiple results use the first one that extends to the end.
            // Then a document of `aa\nb` can match a query of `a\nb`.
            // There is a bug here that a regex query of `a*\nb` should have multiple
            // matches in that document.
            for (ResultRange *candidate in lineResults.reverseObjectEnumerator) {
                if (candidate.position + candidate.length == lineLength) {
                    DLog(@"Accept candidate %@", candidate);
                    range = candidate;
                    break;
                }
            }
        }

        if (!range) {
            DLog(@"No match found satisfying start-at-zero constraint.");
            return nil;
        }

        // Check mustExtendToEnd constraint.
        if (mustExtendToEnd && range.position + range.length != lineLength) {
            DLog(@"The result did not extend to the end so it doesn't match the newline.");
            return nil;
        }

        // Update result based on whether this is the first query line.
        if (isFirstQueryLine) {
            DLog(@"This is the first line of the query.");
            if (backward) {
                // For backward search, we've accumulated length from later query lines.
                // Now set position and add our length plus accumulated.
                multiLineRange = [range mutableCopy];
                multiLineRange.length += accumulatedLength;
            } else {
                // For forward search, this is the first iteration.
                multiLineRange = [range mutableCopy];
            }
            DLog(@"Accept this result by initializing the range to %@.", multiLineRange);
        } else {
            DLog(@"This is not the first line of the query");
            if (backward) {
                // Accumulate length for now; we'll set position when we find the first query line.
                accumulatedLength += range.length;
                DLog(@"Accumulated length is now %d", accumulatedLength);
            } else {
                multiLineRange.length += range.length;
                DLog(@"Accept this line by extending the range to %@.", multiLineRange);
            }
        }
    }
    DLog(@"We found a multi-line result %@", multiLineRange);
    return [LineBlockMultiLineSearchState stateWithResult:multiLineRange];
}

- (void)findSubstring:(NSString *)substring
              options:(FindOptions)options
                 mode:(iTermFindMode)mode
             atOffset:(int)offset
              results:(NSMutableArray *)results
      multipleResults:(BOOL)multipleResults
includesPartialLastLine:(BOOL *)includesPartialLastLine
  multiLinePriorState:(LineBlockMultiLineSearchState *)priorState
    continuationState:(LineBlockMultiLineSearchState **)continuationState
crossBlockResultCount:(NSInteger *)crossBlockResultCount {
    *includesPartialLastLine = NO;
    if (continuationState) {
        *continuationState = nil;
    }
    if (crossBlockResultCount) {
        *crossBlockResultCount = 0;
    }
    if (offset == -1) {
        offset = [self rawSpaceUsed] - 1;
    }
    NSArray<NSString *> *splitLines = nil;
    if (options & FindOptMultiLine) {
        // The purpose of the find option is to avoid having to do this in the normal case.
        splitLines = [substring componentsSeparatedByString:@"\n"];
    }

    // Handle continuation of a partial match from a prior block.
    if (priorState && priorState.needsContinuation && splitLines.count > 1) {
        const BOOL backward = (options & FindOptBackwards) != 0;
        // For forward search, continue at _firstEntry. For backward, continue at the last entry.
        int continuationEntry = backward ? (cll_entries - 1) : _firstEntry;
        LineBlockMultiLineSearchState *state = [self _searchMultiLineFromEntry:continuationEntry
                                                                    splitLines:splitLines
                                                                       options:options
                                                                          mode:mode
                                                                          skip:0
                                                               multipleResults:multipleResults
                                                                    priorState:priorState];
        if (state.result) {
            // Found a complete match spanning blocks.
            // The result's position is relative to the first line of the match.
            // For forward search: first line was in a prior block, use startingBlockPosition.
            // For backward search: first line is in this block, position is already correct
            // (will be adjusted by blockPosition in LineBuffer like normal results).
            if (!backward) {
                state.result->position += priorState.startingBlockPosition;
                if (crossBlockResultCount) {
                    (*crossBlockResultCount)++;
                }
            }
            // For backward, the position needs to be relative to the first query line's entry
            // in this block. We need to add the raw offset of that entry.
            if (backward) {
                // First query line is at entry continuationEntry - (splitLines.count - 1 - priorState.queryLineIndex)
                int firstLineEntry = continuationEntry - ((int)splitLines.count - 1 - (int)priorState.queryLineIndex);
                ITAssertWithMessage(firstLineEntry >= _firstEntry,
                                    @"firstLineEntry=%d < _firstEntry=%d", firstLineEntry, _firstEntry);
                state.result->position += [self _lineRawOffset:firstLineEntry];
            }
            [results addObject:state.result];
            // Check if this cross-block match touches the partial last line.
            if (is_partial) {
                if (!backward) {
                    int lastMatchedEntry = _firstEntry + ((int)splitLines.count - (int)priorState.queryLineIndex - 1);
                    if (lastMatchedEntry == cll_entries - 1) {
                        *includesPartialLastLine = YES;
                    }
                } else {
                    // Backward continuation always starts at the last entry (cll_entries - 1).
                    *includesPartialLastLine = YES;
                }
            }
            if (!multipleResults) {
                return;
            }
        } else if (state.needsContinuation && continuationState) {
            // Still need more blocks to complete the match.
            *continuationState = state;
        }
    }

    int entry;
    int limit;
    int dir;
    if (options & FindOptBackwards) {
        entry = [self _findEntryBeforeOffset:offset];
        if (entry == -1) {
            // Maybe there were no lines or offset was <= self.bufferStartOffset.
            return;
        }
        limit = _firstEntry - 1;
        dir = -1;
    } else {
        entry = _firstEntry;
        limit = cll_entries;
        dir = 1;
    }
    while (entry != limit) {
        int line_raw_offset = [self _lineRawOffset:entry];
        int skipped = offset - line_raw_offset;
        if (skipped < 0) {
            skipped = 0;
        }
        NSMutableArray* newResults = [NSMutableArray arrayWithCapacity:1];

        // Don't search arbitrarily long lines. If someone has a 10 million character long line then
        // it'll hang for a long time.
        static const int MAX_SEARCHABLE_LINE_LENGTH = 30000000;
        int numberOfQueryLines = 1;
        if (options & FindOptMultiLine) {
            DLog(@"Multiline query");
            assert(splitLines.count > 1);
            numberOfQueryLines = splitLines.count;
            // Check if there are enough lines in this block to attempt a multi-line search.
            // For forward search: need lines entry, entry+1, ..., entry+N-1
            // For backward search: need lines entry, entry-1, ..., entry-(N-1)
            BOOL hasEnoughLines;
            if (options & FindOptBackwards) {
                hasEnoughLines = (entry - ((int)splitLines.count - 1) >= _firstEntry);
            } else {
                hasEnoughLines = (entry + (int)splitLines.count <= cll_entries);
            }
            LineBlockMultiLineSearchState *state = nil;
            if (hasEnoughLines) {
                state = [self _searchMultiLineFromEntry:entry
                                            splitLines:splitLines
                                               options:options
                                                  mode:mode
                                                  skip:skipped
                                       multipleResults:multipleResults
                                            priorState:nil];
                if (state.result) {
                    [newResults addObject:state.result];
                }
            } else if (continuationState && *continuationState == nil) {
                // Not enough lines in this block - try to start a partial match that may continue
                // on the next block. Only do this if we don't already have a pending continuation.
                // At most one continuation is ever needed because if entry E doesn't have enough
                // lines, all subsequent entries (E+dir) have even fewer remaining lines in this block.
                state = [self _searchMultiLineFromEntry:entry
                                            splitLines:splitLines
                                               options:options
                                                  mode:mode
                                                  skip:skipped
                                       multipleResults:multipleResults
                                            priorState:nil];
                if (state.needsContinuation) {
                    // Save the partial match state. The position needs to be adjusted by
                    // this entry's raw offset since the result position is relative to the entry.
                    if (state.partialResult) {
                        int positionOffset;
                        if (options & FindOptBackwards) {
                            // For backward, we don't know the first line yet (it's in a prior block)
                            // so we can't adjust position here. We'll handle it when the match completes.
                            positionOffset = 0;
                        } else {
                            positionOffset = line_raw_offset;
                        }
                        state.partialResult->position += positionOffset;
                    }
                    // Track partial last line: for forward search the match
                    // extended to the end of the block (that's why it needs
                    // continuation). For backward, only if we started at the last entry.
                    if (is_partial) {
                        if (!(options & FindOptBackwards)) {
                            *includesPartialLastLine = YES;
                        } else if (entry == cll_entries - 1) {
                            *includesPartialLastLine = YES;
                        }
                    }
                    *continuationState = state;
                    return;
                }
            }
        } else {
            DLog(@"Single-line search");
            [self _findInRawLine:entry
                          needle:substring
                         options:options
                            mode:mode
                            skip:skipped
                          length:MIN(MAX_SEARCHABLE_LINE_LENGTH, [self _lineLength:entry])
                 multipleResults:multipleResults
                         results:newResults];
        }
        for (ResultRange* r in newResults) {
            // For multi-line backward search, the result position is relative to the first line
            // of the match, which is entry - (numberOfQueryLines - 1), not entry.
            int positionOffset;
            if ((options & FindOptMultiLine) && (options & FindOptBackwards)) {
                positionOffset = [self _lineRawOffset:entry - (numberOfQueryLines - 1)];
            } else {
                positionOffset = line_raw_offset;
            }
            r->position += positionOffset;
            [results addObject:r];
        }
        if (newResults.count && is_partial && entry + numberOfQueryLines == cll_entries) {
            *includesPartialLastLine = YES;
        }
        if ([newResults count] && !multipleResults) {
            return;
        }
        entry += dir;
    }
}

// Returns YES if the position is valid for this block.
// If wrapOnEOL is true: if `position` is exactly after a hard EOL, use the start of the subsequent
// line. Otherwise, return the coordinate at the end of the line with the hard EOL.
- (BOOL)convertPosition:(int)position
              withWidth:(int)width
              wrapOnEOL:(BOOL)wrapOnEOL
                    toX:(int*)x
                    toY:(int*)y {
    if (width <= 0) {
        return NO;
    }
    int i;
    *x = 0;
    *y = 0;
    int prev = self.bufferStartOffset;
    const screen_char_t *p = _characterBuffer.pointer;
    for (i = _firstEntry; i < cll_entries; ++i) {
        int eol = cumulative_line_lengths[i];
        int line_length = eol - prev;
        if ((wrapOnEOL && position >= eol) || (!wrapOnEOL && position > eol)) {
            // Get the number of full-width lines in the raw line. If there were
            // only single-width characters the formula would be:
            //     spans = (line_length - 1) / width;
            int spans = [self numberOfFullLinesFromOffset:prev
                                                   length:line_length
                                                    width:width];

            *y += spans + 1;
        } else {
            // The position we're searching for is in this (unwrapped) line.
            int bytes_to_consume_in_this_line = position - prev;
            int dwc_peek = 0;

            // If the position is the left half of a double width char then include the right half in
            // the following call to numberOfFullLinesFromOffset:length:width:.

            if (bytes_to_consume_in_this_line < line_length &&
                prev + bytes_to_consume_in_this_line + 1 < eol) {
                assert(prev + bytes_to_consume_in_this_line + 1 < _characterBuffer.size);
                const int i = prev + bytes_to_consume_in_this_line + 1;
                const screen_char_t c = p[i];
                if (width > 1 && ScreenCharIsDWC_RIGHT(c)) {
                    ++dwc_peek;
                }
            }
            int consume = [self numberOfFullLinesFromOffset:prev
                                                     length:MIN(line_length, bytes_to_consume_in_this_line + 1 + dwc_peek)
                                                      width:width];
            *y += consume;
            if (consume > 0) {
                // Offset from prev where the consume'th line begin.
                int offset = [self cacheAwareOffsetOfWrappedLineInBuffer:LineBlockMakeLocation(prev - _startOffset, line_length, i)
                                                       wrappedLineNumber:consume
                                                                   width:width];
                // We know that position falls in this line. Set x to the number
                // of chars after the beginning on the line. If there were only
                // single-width chars the formula would be:
                //     bytes_to_consume_in_this_line % (consume * width);
                *x = position - (prev + offset);
            } else {
                *x = MAX(0, bytes_to_consume_in_this_line);
            }
            return YES;
        }
        prev = eol;
    }
    VLog(@"Didn't find position %d", position);
    return NO;
}

- (NSArray *)cumulativeLineLengthsArray {
    NSMutableArray *cllArray = [NSMutableArray array];
    for (int i = 0; i < cll_entries; i++) {
        [cllArray addObject:@(cumulative_line_lengths[i])];
    }
    return cllArray;
}

- (NSArray *)metadataArray {
    NSArray *result = [_metadataArray encodedArray];
    assert(result != nil);
    return result;
}

- (NSDictionary *)dictionary {
    return @{ kLineBlockRawBufferV3Key: _characterBuffer.data,
              kLineBlockBufferStartOffsetKey: @(self.bufferStartOffset),
              kLineBlockStartOffsetKey: @(self.bufferStartOffset),
              kLineBlockFirstEntryKey: @(_firstEntry),
              kLineBlockBufferSizeKey: @(_characterBuffer.size),
              kLineBlockCLLKey: [self cumulativeLineLengthsArray],
              kLineBlockIsPartialKey: @(is_partial),
              kLineBlockMetadataKey: [self metadataArray],
              kLineBlockMayHaveDWCKey: @(_mayHaveDoubleWidthCharacter),
              kLineBlockGuid: _guid };
}

- (int)numberOfCharacters {
    return self.rawSpaceUsed - self.bufferStartOffset;
}

- (int)numberOfTrailingEmptyLines {
    int count = 0;
    for (int i = cll_entries - 1; i >= _firstEntry; i--) {
        if ([self lengthOfRawLine:i] == 0) {
            count++;
        } else {
            break;
        }
    }
    return count;
}

- (int)numberOfLeadingEmptyLines {
    int count = 0;
    for (int i = _firstEntry; i < cll_entries; i++) {
        if ([self lengthOfRawLine:i] == 0) {
            count++;
        } else {
            break;
        }
    }
    return count;
}

- (BOOL)containsAnyNonEmptyLine {
    if (cll_entries == 0) {
        return NO;
    }
    return cumulative_line_lengths[cll_entries - 1] > self.bufferStartOffset;
}

#pragma mark - COW

// On exit, these postconditions are guaranteed:
// self.owner==nil
// self.clients.arrayByStrongifyingWeakBoxes.count==0.
- (id<iTermLineBlockMutationCertificate>)validMutationCertificate {
    // The access to _hasBeenCopied is not a race because the line block must be copied on the
    // same thread that mutates it.
    if (!self.hasBeenCopied) {
        if (!_cachedMutationCert) {
            _cachedMutationCert = [[iTermLineBlockMutator alloc] initWithLineBlock:self];
        }
        return (id<iTermLineBlockMutationCertificate>)_cachedMutationCert;
    }

    {
        std::lock_guard<std::recursive_mutex> lock(gLineBlockMutex);

        [_metadataArray willMutate];

        if (!_cachedMutationCert) {
            _cachedMutationCert = [[iTermLineBlockMutator alloc] initWithLineBlock:self];
        }
        assert(self.clients != nil);

        if (self.owner == nil && self.clients.count == 0) {
            // I have neither an owner nor clients, so copy-on-write is unneeded.
            [self.clients prune];
            return (id<iTermLineBlockMutationCertificate>)_cachedMutationCert;
        }

        NSArray<LineBlock *> *myClients = (NSArray<LineBlock *> *)self.clients.strongObjects;
        const NSUInteger numberOfClients = myClients.count;

        // Perform copy-on-write copying.
        const ptrdiff_t offset = self.bufferStartOffset;
        _characterBuffer = [_characterBuffer clone];
        [self setBufferStartOffset:offset];
        iTermAssignToConstPointer((void **)&cumulative_line_lengths, iTermMemdup(self->cumulative_line_lengths, cll_capacity, sizeof(int)));

        if (self.owner != nil) {
            // This copy is diverging from its progenitor by mutating.
            // Mark it so incremental merge knows not to use it.
            _hasDiverged = YES;

            // I am no longer a client. Remove myself from my owner's client list.
            [self.owner.clients removeObjectsPassingTest:^BOOL(id block) {
                return block == self;
            }];
            // Since I am not a client anymore, I now have no owner.
            self.owner = nil;
        }

        if (numberOfClients == 0) {
            // I have no clients.
            // Nothing else to do since my owner pointer was already nilled out.
            [self.clients removeAllObjects];
            return (id<iTermLineBlockMutationCertificate>)_cachedMutationCert;
        }

        // I have one or more clients.
        assert(numberOfClients >= 1);

        // Designate the first client as the owner.
        LineBlock *newOwner = myClients[0];

        // The new owner should not have an owner anymore.
        assert(newOwner.owner == self);
        newOwner.owner = nil;

        // Transfer ownership of additional clients to newOwner.
        for (LineBlock *client in [myClients subarrayFromIndex:1]) {
            assert(client != newOwner);
            client.owner = newOwner;
            [newOwner.clients addObject:client];
        }

        // All clients were transferred and now I should have none.
        [self.clients removeAllObjects];

        return (id<iTermLineBlockMutationCertificate>)_cachedMutationCert;
    }
}

- (LineBlock *)cowCopy {
    std::lock_guard<std::recursive_mutex> lock(gLineBlockMutex);

    self.hasBeenCopied = YES;
    // Make a shallow copy, sharing memory with me (and I may even be a shallow copy of some other LineBlock).
    LineBlock *copy = [self copyDeep:NO absoluteBlockNumber:_absoluteBlockNumber];

    // Walk owner pointers up to the root.
    LineBlock *owner = self;
    while (owner.owner) {
        owner = owner.owner;
    }

    // Create ownership relation.
    copy.owner = owner;
    [owner.clients addObject:copy];

    [(id<iTermLineBlockMutationCertificate>)_cachedMutationCert invalidate];
    _cachedMutationCert = nil;
    copy->_progenitor = self;

    // Reset append tracking - new copies start clean
    _appendOnlySinceLastCopy = YES;

    return copy;
}

- (NSInteger)numberOfClients {
    if (!self.hasBeenCopied) {
        return 0;
    }
    {
        std::lock_guard<std::recursive_mutex> lock(gLineBlockMutex);
        return self.clients.count;
    }
}

- (void)initializeClients {
    self.clients = [[iTermLegacyAtomicMutableArrayOfWeakObjects alloc] init];
}

- (BOOL)hasOwner {
    std::lock_guard<std::recursive_mutex> lock(gLineBlockMutex);
    return self.owner != nil;
}

- (void)invalidate {
    // The purpose of invalidation is to make syncing do the right thing when the progenitor block
    // is removed from the line buffer.
    _invalidated = YES;
}

#pragma mark - iTermUniquelyIdentifiable

- (NSString *)stringUniqueIdentifier {
    return _guid;
}

@end

@implementation iTermLineBlockMutator {
    __weak LineBlock *_lineBlock;

    // Validity is tracked to catch bugs where you do a cowCopy followed by a mutation using an existing cert.
    BOOL _valid;
}
- (instancetype)initWithLineBlock:(LineBlock *)lineBlock {
    self = [super init];
    if (self) {
        _valid = YES;
        _lineBlock = lineBlock;
    }
    return self;
}

#pragma mark - iTermLineBlockMutationCertificate

- (void)invalidate {
    _valid = NO;
}

- (int *)mutableCumulativeLineLengths {
    assert(_valid);
    return (int *)_lineBlock->cumulative_line_lengths;
}

- (screen_char_t *)mutableRawBuffer {
    assert(_valid);
    return _lineBlock->_characterBuffer.mutablePointer;
}

- (void)setRawBufferCapacity:(size_t)count {
    assert(_valid);
    [_lineBlock->_characterBuffer resize:count];
}

- (void)setCumulativeLineLengthsCapacity:(int)capacity {
    assert(_valid);
    iTermAssignToConstPointer((void **)&_lineBlock->cumulative_line_lengths,
                              iTermRealloc((void *)_lineBlock->cumulative_line_lengths, capacity, sizeof(int)));
}

@end
