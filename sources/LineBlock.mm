//
//  LineBlock.m
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

extern "C" {
#import "LineBlock.h"
#import "DebugLogging.h"
#import "FindContext.h"
#import "iTermExternalAttributeIndex.h"
#import "iTermMalloc.h"
#import "iTermMetadata.h"
#import "iTermWeakBox.h"
#import "LineBufferHelpers.h"
#import "NSArray+iTerm.h"
#import "NSBundle+iTerm.h"
#import "RegexKitLite.h"
#import "iTermAdvancedSettingsModel.h"
}

// BEGIN C++ HEADERS - No C headers here!
#include <unordered_map>
#include <vector>

static BOOL gEnableDoubleWidthCharacterLineCache = NO;
static BOOL gUseCachingNumberOfLines = NO;

NSString *const kLineBlockRawBufferV1Key = @"Raw Buffer";  // v1 - uses legacy screen_char_t format.
NSString *const kLineBlockRawBufferV2Key = @"Raw Buffer v2";  // v2 - used 0xf000-0xf003 for DWC_SKIP and friends.
NSString *const kLineBlockRawBufferV3Key = @"Raw Buffer v3";  // v3 - uses 0x0001-0x0004 for DWC_SKIP and friends
NSString *const kLineBlockBufferStartOffsetKey = @"Buffer Start Offset";
NSString *const kLineBlockStartOffsetKey = @"Start Offset";
NSString *const kLineBlockFirstEntryKey = @"First Entry";
NSString *const kLineBlockBufferSizeKey = @"Buffer Size";
NSString *const kLineBlockCLLKey = @"Cumulative Line Lengths";
NSString *const kLineBlockIsPartialKey = @"Is Partial";
NSString *const kLineBlockMetadataKey = @"Metadata";
NSString *const kLineBlockMayHaveDWCKey = @"May Have Double Width Character";
NSString *const kLineBlockGuid = @"GUID";

#ifdef DEBUG_SEARCH
@interface NSString(LineBlockDebugging)
@end

@implementation NSString(LineBlockDebugging)
- (NSString *)asciified {
    NSMutableString *c = [self mutableCopy];
    NSRange range = [c rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 32)]];
    while (range.location != NSNotFound) {
        [c replaceCharactersInRange:range withString:@"."];
        range = [c rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 32)]];
    }
    return c;
}
@end
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

typedef struct {
    BOOL found;
    int prev;
    int numEmptyLines;
    int index;
    int length;
} LineBlockLocation;

const unichar kPrefixChar = REGEX_START;
const unichar kSuffixChar = REGEX_END;

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

@interface LineBlock()
// These are synchronzed on [LineBlock class]. Sample graph:
//
// Begin with just one LineBlock, A:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o--------------------------> [o, o]
// | buffer    |o---> [malloced memory]       :  :
// +-----------+                    ^         :  :
//
// Now call -cowCopy on it to create B, and you get:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o--------------------------> [o]
// | buffer    |o---> [malloced memory]       :
// +-----------+                    ^         :
//       ^                          |         :
//       |             ,- - - - - - ) - - -  -'
//       |             :            |
//       |             V            |
//       |       B-----------+      |
//       |       | LineBlock |      |
//       |       |-----------|      |
//       |       | buffer    |o-----'
//       `------o| owner     |
//               | clients   |o---> []
//               +-----------+
//
// Calling -cowCopy again on either A or B gives C, resulting in this state:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o--------------------------> [o, o]
// | buffer    |o---> [malloced memory]       :  :
// +-----------+                    ^         :  :
//       ^                          |         :  :
//       |             ,- - - - - - ) - - -  -'  ` - - - -,
//       |             :            |                   :
//       |             V            |                   V
//       |       B-----------+      |             C-----------+
//       |       | LineBlock |      |             | LineBlock |
//       |       |-----------|      |             |-----------|
//       |       | buffer    |o-----+------------o| buffer    |
//       +------o| owner     |               .---o| owner     |
//       |       | clients   |o---> []       |    | clients   |o---> []
//       |       +-----------+               |    +-----------+
//       |                                   |
//       `-----------------------------------'
//
// If you modify A (an owner) then you get this situation:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o---> []
// | buffer    |o---> [copy of malloced memory]
// +-----------+
//                    [original malloced memory]
//                                  ^
//                                  |
//               B-----------+      |             C-----------+
//               | LineBlock |      |             | LineBlock |
//               |-----------|      |             |-----------|
//               | buffer    |o-----+------------o| buffer    |
//               | owner     |<------------------o| owner     |
//               | clients   |o---> [o]           | clients   |o---> []
//               +-----------+       |            +-----------+
//                                   |                  ^
//                                   |                  |
//                                   `------------------`
//  From here, if you modify C (a client) you get:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o---> []
// | buffer    |o---> [copy of malloced memory]
// +-----------+
//                    [original malloced memory]
//                                  ^
//                                  |
//               B-----------+      |             C-----------+
//               | LineBlock |      |             | LineBlock |
//               |-----------|      |             |-----------|
//               | buffer    |o-----`             | buffer    |o---> [another copy of malloced memory]
//               | owner     |o---> nil           | owner     |o---> nil
//               | clients   |o---> []            | clients   |o---> []
//               +-----------+                    +-----------+
//
// Clients strongly retain their owners. That means that when a LineBlock is dealloced, it must have
// no clients and it is safe to free memory.
// When a client gets dealloced it does not need to free memory.
// An owner "owns" the memory and is responsible for freeing it.
// When owner is nonnil or clients is not empty, a copy must be made before mutation.
// Use -modifyWithBlock: to get a iTermLineBlockMutationCertificate which allows mutation safely because
// you can't get a certificate without copying (if needed).
@property(nonatomic) LineBlock *owner;  // nil if I am an owner. This is the line block that is responsible for freeing malloced data.
@property(nonatomic) NSMutableArray<iTermWeakBox<LineBlock *> *> *clients;  // Copy-on write instances that still exist and have me as the owner.
@end

// Use iTermAssignToConstPointer if you need to change anything that is `const T * const` to make
// these calls auditable to ensure we call validMutationCertificate appropriately.
@implementation LineBlock {
@public
    // The raw lines, end-to-end. There is no delimiter between each line.

    // NOTE: The fields with commented-out const annotations *are* const but I removed them to see
    // if I was hitting UB. See crash in 3.5.0beta5 1648809545.408710187.txt.

//    const screen_char_t * const raw_buffer;
    screen_char_t *raw_buffer;
//    const screen_char_t *buffer_start;  // Points into raw_buffer's buffer. Gives the usable start of buffer (stuff before this is dropped).
    screen_char_t *buffer_start;

    int start_offset;  // distance from raw_buffer to buffer_start
    int first_entry;  // first valid cumulative_line_length

    // The number of elements allocated for raw_buffer.
    int buffer_size;

    // There will be as many entries in this array as there are lines in raw_buffer.
    // The ith value is the length of the ith line plus the value of
    // cumulative_line_lengths[i-1] for i>0 or 0 for i==0.
//    const int * const cumulative_line_lengths;
    int *cumulative_line_lengths;
    LineBlockMetadata *metadata_;

    // The number of elements allocated for cumulative_line_lengths.
    int cll_capacity;

    // The number of values in the cumulative_line_lengths array.
    int cll_entries;

    // If true, then the last raw line does not include a logical newline at its terminus.
    BOOL is_partial;

    // The number of wrapped lines if width==cached_numlines_width.
    int cached_numlines;

    // This is -1 if the cache is invalid; otherwise it specifies the width for which
    // cached_numlines is correct.
    int cached_numlines_width;

    // Keys are (offset from raw_buffer, length to examine, width).
    std::unordered_map<iTermNumFullLinesCacheKey, int, iTermNumFullLinesCacheKeyHasher> _numberOfFullLinesCache;

    NSMutableArray<iTermWeakBox<id<iTermLineBlockObserver>> *> *_observers;
    NSString *_guid;

    NSObject *_cachedMutationCert;  // DON'T USE DIRECTLY THIS UNLESS YOU LOVE PAIN. Only -validMutationCertificate should touch it.
}

NS_INLINE void iTermLineBlockDidChange(__unsafe_unretained LineBlock *lineBlock) {
    lineBlock->_generation += 1;
    for (iTermWeakBox<id<iTermLineBlockObserver>> *box in lineBlock->_observers) {
        [box.object lineBlockDidChange:lineBlock];
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

//static void iTermAssignToConstPointer(void **dest, void *address) {
//    *dest = address;
//}
#define iTermAssignToConstPointer(dest, address) (*(dest) = (address))

- (LineBlock *)initWithRawBufferSize:(int)size {
    self = [super init];
    if (self) {
        iTermAssignToConstPointer((void **)&raw_buffer, iTermMalloc(sizeof(screen_char_t) * size));
        buffer_start = raw_buffer;
        buffer_size = size;
        // Allocate enough space for a bunch of 80-character lines. It can grow if needed.
        cll_capacity = 1 + size/80;
        iTermAssignToConstPointer((void **)&cumulative_line_lengths, iTermMalloc(sizeof(int) * cll_capacity));
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([iTermAdvancedSettingsModel dwcLineCache]) {
            gEnableDoubleWidthCharacterLineCache = YES;
            gUseCachingNumberOfLines = YES;
        }
    });
    _observers = [NSMutableArray array];
    if (!_guid) {
        _guid = [[NSUUID UUID] UUIDString];
    }
    cached_numlines_width = -1;
    if (cll_capacity > 0) {
        metadata_ = (LineBlockMetadata *)iTermCalloc(sizeof(LineBlockMetadata), cll_capacity);
    }
    self.clients = [NSMutableArray array];
}

+ (instancetype)blockWithDictionary:(NSDictionary *)dictionary {
    return [[self alloc] initWithDictionary:dictionary];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
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
        if (dictionary[kLineBlockRawBufferV3Key]) {
            data = dictionary[kLineBlockRawBufferV3Key];
        } else if (dictionary[kLineBlockRawBufferV2Key]) {
            data = [dictionary[kLineBlockRawBufferV2Key] migrateV2ToV3];
            _generation = 1;
        } else if (dictionary[kLineBlockRawBufferV1Key]) {
            data = [dictionary[kLineBlockRawBufferV1Key] migrateV1ToV3:&migrationIndex];
            _generation = 1;
        }
        if (!data) {
            return nil;
        }
        buffer_size = [dictionary[kLineBlockBufferSizeKey] intValue];
        iTermAssignToConstPointer((void **)&raw_buffer, iTermMalloc(buffer_size * sizeof(screen_char_t)));
        memmove((void *)raw_buffer, data.bytes, data.length);
        buffer_start = raw_buffer + [dictionary[kLineBlockBufferStartOffsetKey] intValue];
        start_offset = [dictionary[kLineBlockStartOffsetKey] intValue];
        first_entry = [dictionary[kLineBlockFirstEntryKey] intValue];
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
            int j = 0;
            NSArray *components = metadataArray[i];
            metadata_[i].continuation.code = [components[j++] unsignedShortValue];
            metadata_[i].continuation.backgroundColor = [components[j++] unsignedCharValue];
            metadata_[i].continuation.bgGreen = [components[j++] unsignedCharValue];
            metadata_[i].continuation.bgBlue = [components[j++] unsignedCharValue];
            metadata_[i].continuation.backgroundColorMode = [components[j++] unsignedCharValue];
            NSNumber *timestamp = components.count > j ? components[j++] : @0;

            // If a migration index is present, use it. Migration loses external attributes, but
            // at least for the v1->v2 transition it's not important because only underline colors
            // get lost when they occur on the same line as a URL.
            iTermExternalAttributeIndex *eaIndex =
                [migrationIndex subAttributesFromIndex:startOffset
                                         maximumLength:cumulative_line_lengths[i] - startOffset];
            if (!eaIndex.attributes.count) {
                NSDictionary *encodedExternalAttributes = components.count > j ? components[j++] : nil;
                if ([encodedExternalAttributes isKindOfClass:[NSDictionary class]]) {
                    eaIndex = [[iTermExternalAttributeIndex alloc] initWithDictionary:encodedExternalAttributes];
                }
            } else if (components.count > j) {
                j += 1;
            }

            iTermMetadataInit(&metadata_[i].lineMetadata,
                              timestamp.doubleValue,
                              eaIndex);
            metadata_[i].number_of_wrapped_lines = 0;
            if (gEnableDoubleWidthCharacterLineCache) {
                metadata_[i].double_width_characters = nil;
            }
            startOffset = cumulative_line_lengths[i];
        }

        cll_entries = cll_capacity;
        is_partial = [dictionary[kLineBlockIsPartialKey] boolValue];
        _mayHaveDoubleWidthCharacter = [dictionary[kLineBlockMayHaveDWCKey] boolValue];
    }
    return self;
}

static void iTermLineBlockFreeMetadata(LineBlockMetadata *metadata, int count) {
    if (!metadata) {
        return;
    }
    if (gEnableDoubleWidthCharacterLineCache) {
        for (int i = 0; i < count; i++) {
            metadata[i].double_width_characters = nil;
        }
    }
    for (int i = 0; i < count; i++) {
        iTermMetadataRelease(metadata[i].lineMetadata);
    }
    free(metadata);
}

- (void)dealloc {
    BOOL shouldFreeBuffers = YES;
    @synchronized([LineBlock class]) {
        if (self.owner != nil) {
            shouldFreeBuffers = NO;
            // I don't own my memory so I should not free it. Remove myself from the owner's client
            // list to ensure its list of clients doesn't get too big.f
            [self.owner.clients removeObjectsPassingTest:^BOOL(iTermWeakBox<LineBlock *> *box) {
                return box.object == self || box.object == nil;
            }];
        }
    }

    if (shouldFreeBuffers) {
        if (raw_buffer) {
            free((void *)raw_buffer);
        }
        if (cumulative_line_lengths) {
            free((void *)cumulative_line_lengths);
        }
    }
    if (metadata_) {
        iTermLineBlockFreeMetadata(metadata_, cll_capacity);
    }
}

- (LineBlock *)copyWithZone:(NSZone *)zone {
    return [self copyDeep:YES];
}

- (void)copyMetadataTo:(LineBlock *)theCopy {
    // This is an opportunity for optimization, perhaps. We don't do COW for metadata but we could.
    iTermLineBlockFreeMetadata(theCopy->metadata_, theCopy->cll_capacity);
    theCopy->metadata_ = (LineBlockMetadata *)iTermCalloc(cll_capacity, sizeof(LineBlockMetadata));
    // Copy metadata field by field to please arc (memmove doesn't work right!)
    for (int i = 0; i < cll_capacity; i++) {
        LineBlockMetadata *theirs = (LineBlockMetadata *)&theCopy->metadata_[i];

        iTermExternalAttributeIndex *index = iTermMetadataGetExternalAttributesIndex(metadata_[i].lineMetadata);
        iTermExternalAttributeIndex *indexCopy = [index copy];
        iTermMetadataInit(&theirs->lineMetadata,
                          metadata_[i].lineMetadata.timestamp,
                          indexCopy);

        theirs->continuation = metadata_[i].continuation;
        theirs->number_of_wrapped_lines = 0;
        theirs->width_for_number_of_wrapped_lines = 0;
        if (gEnableDoubleWidthCharacterLineCache) {
            theirs->double_width_characters = nil;
        }
        theirs->width_for_double_width_characters_cache = 0;
    }
}

- (LineBlock *)copyDeep:(BOOL)deep {
    LineBlock *theCopy = [[LineBlock alloc] init];
    if (!deep) {
        iTermAssignToConstPointer((void **)&theCopy->raw_buffer, (void *)raw_buffer);
        theCopy->buffer_start = buffer_start;
        theCopy->start_offset = start_offset;
        theCopy->first_entry = first_entry;
        theCopy->buffer_size = buffer_size;
        iTermAssignToConstPointer((void **)&theCopy->cumulative_line_lengths, (void *)cumulative_line_lengths);
        [self copyMetadataTo:theCopy];
        theCopy->cll_capacity = cll_capacity;
        theCopy->cll_entries = cll_entries;
        theCopy->is_partial = is_partial;
        theCopy->cached_numlines = cached_numlines;
        theCopy->cached_numlines_width = cached_numlines_width;
        // Don't copy the cache because doing so is expensive. I blame C++.
        theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;

        // Preserve these so delta encoding will continue to work when you encode a copy.
        theCopy->_generation = _generation;
        theCopy->_guid = [_guid copy];

        return theCopy;
    }
    iTermAssignToConstPointer((void **)&theCopy->raw_buffer, iTermMalloc(sizeof(screen_char_t) * buffer_size));
    memmove((void *)theCopy->raw_buffer, raw_buffer, sizeof(screen_char_t) * buffer_size);
    size_t bufferStartOffset = (buffer_start - raw_buffer);
    theCopy->buffer_start = theCopy->raw_buffer + bufferStartOffset;
    theCopy->start_offset = start_offset;
    theCopy->first_entry = first_entry;
    theCopy->buffer_size = buffer_size;
    size_t cll_size = sizeof(int) * cll_capacity;
    iTermAssignToConstPointer((void **)&theCopy->cumulative_line_lengths, iTermMalloc(cll_size));

    memmove((void *)theCopy->cumulative_line_lengths,
            (const void *)cumulative_line_lengths,
            cll_size);
    [self copyMetadataTo:theCopy];
    theCopy->cll_capacity = cll_capacity;
    theCopy->cll_entries = cll_entries;
    theCopy->is_partial = is_partial;
    theCopy->cached_numlines = cached_numlines;
    theCopy->cached_numlines_width = cached_numlines_width;
    theCopy->_generation = _generation;
    theCopy->_guid = [_guid copy];
    theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;

    return theCopy;
}

- (int)rawSpaceUsed {
    if (cll_entries == 0) {
        return 0;
    } else {
        return cumulative_line_lengths[cll_entries - 1];
    }
}

- (void)_appendCumulativeLineLength:(int)cumulativeLength
                           metadata:(iTermImmutableMetadata)lineMetadata
                       continuation:(screen_char_t)continuation
                               cert:(id<iTermLineBlockMutationCertificate>)cert {
    if (cll_entries == cll_capacity) {
        cll_capacity *= 2;
        cll_capacity = MAX(1, cll_capacity);
        [cert setCumulativeLineLengthsCapacity:cll_capacity];
        metadata_ = (LineBlockMetadata *)iTermRealloc((void *)metadata_, cll_capacity, sizeof(LineBlockMetadata));
        if (gEnableDoubleWidthCharacterLineCache) {
            memset((LineBlockMetadata *)metadata_ + cll_entries,
                   0,
                   sizeof(LineBlockMetadata) * (cll_capacity - cll_entries));
        }
    }
    ((int *)cumulative_line_lengths)[cll_entries] = cumulativeLength;
    iTermMetadataAutorelease(metadata_[cll_entries].lineMetadata);
    metadata_[cll_entries].lineMetadata = iTermImmutableMetadataMutableCopy(lineMetadata);
    metadata_[cll_entries].continuation = continuation;
    metadata_[cll_entries].number_of_wrapped_lines = 0;

    ++cll_entries;
}

// used by dump to format a line of screen_char_t's into an asciiz string.
static char* formatsct(const screen_char_t* src, int len, char* dest) {
    if (len > 999) len = 999;
    int i;
    for (i = 0; i < len; ++i) {
        dest[i] = (src[i].code && !src[i].complexChar) ? src[i].code : '.';
    }
    dest[i] = 0;
    return dest;
}

- (void)appendToDebugString:(NSMutableString *)s
{
    char temp[1000];
    int i;
    int prev;
    if (first_entry > 0) {
        prev = cumulative_line_lengths[first_entry - 1];
    } else {
        prev = 0;
    }
    for (i = first_entry; i < cll_entries; ++i) {
        BOOL iscont = (i == cll_entries-1) && is_partial;
        formatsct(buffer_start + prev - start_offset,
                  cumulative_line_lengths[i] - prev,
                  temp);
        [s appendFormat:@"%s%c\n",
         temp,
         iscont ? '+' : '!'];
        prev = cumulative_line_lengths[i];
    }
}

- (void)dump:(int)rawOffset toDebugLog:(BOOL)toDebugLog {
    if (toDebugLog) {
        DLog(@"numRawLines=%@", @([self numRawLines]));
    } else {
        NSLog(@"numRawLines=%@", @([self numRawLines]));
    }
    char temp[1000];
    int i;
    int prev;
    if (first_entry > 0) {
        prev = cumulative_line_lengths[first_entry - 1];
    } else {
        prev = 0;
    }
    for (i = first_entry; i < cll_entries; ++i) {
        BOOL iscont = (i == cll_entries-1) && is_partial;
        NSString *message = [NSString stringWithFormat:@"Line %d, length %d, offset from raw=%d, abs pos=%d, continued=%s: %s\n", i, cumulative_line_lengths[i] - prev, prev, prev + rawOffset, iscont?"yes":"no",
                             formatsct(buffer_start+prev-start_offset, cumulative_line_lengths[i]-prev, temp)];
        NSString *md = iTermMetadataShortDescription(metadata_[i].lineMetadata, cumulative_line_lengths[i] - prev);
        if (toDebugLog) {
            DLog(@"%@%@", message, md);
        } else {
            NSLog(@"%@%@", message, md);
        }
        prev = cumulative_line_lengths[i];
    }
}

- (int)numberOfFullLinesFromOffset:(int)offset
                            length:(int)length
                             width:(int)width {
    auto key = iTermNumFullLinesCacheKey(offset, length, width);
    int result;
    auto insertResult = _numberOfFullLinesCache.insert(std::make_pair(key, -1));
    auto it = insertResult.first;
    auto wasInserted = insertResult.second;
    if (wasInserted) {
        result = iTermLineBlockNumberOfFullLinesImpl(raw_buffer + offset,
                                                     length,
                                                     width,
                                                     _mayHaveDoubleWidthCharacter);
        it->second = result;
    } else {
        result = it->second;
    }

    return result;
}

- (int)numberOfFullLinesFromBuffer:(const screen_char_t *)buffer
                            length:(int)length
                             width:(int)width {
    return [self numberOfFullLinesFromOffset:buffer - raw_buffer
                                      length:length
                                       width:width];
}

extern "C" int iTermLineBlockNumberOfFullLinesImpl(const screen_char_t *buffer,
                                                   int length,
                                                   int width,
                                                   BOOL mayHaveDoubleWidthCharacter) {
    if (width > 1 && mayHaveDoubleWidthCharacter) {
        int fullLines = 0;
        for (int i = width; i < length; i += width) {
            if (ScreenCharIsDWC_RIGHT(buffer[i])) {
                --i;
            }
            ++fullLines;
        }
        return fullLines;
    } else {
        // Need to use max(0) because otherwise we get -1 for length=0 width=1.
        return MAX(0, length - 1) / width;
    }
}

#ifdef TEST_LINEBUFFER_SANITY
- (void) checkAndResetCachedNumlines: (char *) methodName width: (int) width
{
    int old_cached = cached_numlines;
    Boolean was_valid = cached_numlines_width != -1;
    cached_numlines_width = -1;
    int new_cached = [self getNumLinesWithWrapWidth: width];
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
    NSNumber *number =
    [self modifyWithBlock:^id(id<iTermLineBlockMutationCertificate> cert) {
        const BOOL result = [self reallyAppendLine:buffer
                                            length:length
                                           partial:partial
                                             width:width
                                          metadata:lineMetadata
                                      continuation:continuation
                                              cert:cert];
        return @(result);
    }];
    return number.boolValue;
}

- (BOOL)reallyAppendLine:(const screen_char_t*)buffer
                  length:(int)length
                 partial:(BOOL)partial
                   width:(int)width
                metadata:(iTermImmutableMetadata)lineMetadata
            continuation:(screen_char_t)continuation
                    cert:(id<iTermLineBlockMutationCertificate>)cert {
    _numberOfFullLinesCache.clear();
    const int space_used = [self rawSpaceUsed];
    const int free_space = buffer_size - space_used - start_offset;
    if (length > free_space) {
        return NO;
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
    if (is_partial && !(!partial && length == 0)) {
        // append to an existing line
        ITAssertWithMessage(cll_entries > 0, @"is_partial but has no entries");
        // update the numlines cache with the new number of full lines that the updated line has.
        if (width != cached_numlines_width) {
            cached_numlines_width = -1;
        } else {
            int prev_cll = cll_entries > first_entry + 1 ? cumulative_line_lengths[cll_entries - 2] - start_offset : 0;
            int cll = cumulative_line_lengths[cll_entries - 1] - start_offset;
            int old_length = cll - prev_cll;
            int oldnum = [self numberOfFullLinesFromOffset:(buffer_start - raw_buffer) + prev_cll
                                                    length:old_length
                                                     width:width];
            int newnum = [self numberOfFullLinesFromOffset:(buffer_start - raw_buffer) + prev_cll
                                                    length:old_length + length
                                                     width:width];
            cached_numlines += newnum - oldnum;
        }

        int originalLength = cumulative_line_lengths[cll_entries - 1];
        if (cll_entries != first_entry + 1) {
            const int start = cumulative_line_lengths[cll_entries - 2] - start_offset;
            originalLength -= start;
        }
        cert.mutableCumulativeLineLengths[cll_entries - 1] += length;
        iTermMetadataAppend(&metadata_[cll_entries - 1].lineMetadata,
                            originalLength,
                            &lineMetadata,
                            length);
        metadata_[cll_entries - 1].continuation = continuation;
        metadata_[cll_entries - 1].number_of_wrapped_lines = 0;
        if (gEnableDoubleWidthCharacterLineCache) {
            // TODO: Would be nice to add on to the index set instead of deleting it.
            metadata_[cll_entries - 1].double_width_characters = nil;
        }
#ifdef TEST_LINEBUFFER_SANITY
        [self checkAndResetCachedNumlines:@"appendLine partial case" width: width];
#endif
    } else {
        // add a new line
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
        [self checkAndResetCachedNumlines:"appendLine normal case" width: width];
#endif
    }
    is_partial = partial;

    iTermLineBlockDidChange(self);
    return YES;
}

- (LineBlockMetadata)internalMetadataForLine:(int)line {
    return metadata_[line];
}

- (int)getPositionOfLine:(int *)lineNum
                     atX:(int)x
               withWidth:(int)width
                 yOffset:(int *)yOffsetPtr
                 extends:(BOOL *)extendsPtr {
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
        pos = p - raw_buffer + length;
    } else {
        VLog(@"getPositionOfLine: Clear extends and advance pos by x");
        *extendsPtr = NO;
        pos = p - raw_buffer + x;
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
            // First sell of second-or-later line in block.
            *yOffsetPtr += 1;
            VLog(@"getPositionOfLine: First cell of 2nd or later line, advance yOffset to %@", @(*yOffsetPtr));
        }
    }
    VLog(@"getPositionOfLine: getPositionOfLine returning %@, lineNum=%@ yOffset=%@ extends=%@",
          @(pos), @(*lineNum), @(*yOffsetPtr), @(*extendsPtr));
    return pos;
}

- (void)populateDoubleWidthCharacterCacheInMetadata:(LineBlockMetadata *)metadata
                                             buffer:(const screen_char_t *)p
                                             length:(int)length
                                              width:(int)width {
    assert(gEnableDoubleWidthCharacterLineCache);
    metadata->double_width_characters = [[NSMutableIndexSet alloc] init];
    metadata->width_for_double_width_characters_cache = width;

    if (width < 2) {
        return;
    }
    int lines = 0;
    int i = 0;
    while (i + width < length) {
        // Advance i to the start of the next line
        i += width;
        ++lines;
        if (ScreenCharIsDWC_RIGHT(p[i])) {
            // Oops, the line starts with the second half of a double-width
            // character. Wrap the last character of the previous line on to
            // this line.
            i--;
            [metadata->double_width_characters addIndex:lines];
        }
    }
}

- (int)offsetOfWrappedLineInBuffer:(const screen_char_t *)p
                 wrappedLineNumber:(int)n
                      bufferLength:(int)length
                             width:(int)width
                          metadata:(LineBlockMetadata *)metadata {
    assert(gEnableDoubleWidthCharacterLineCache);
    ITBetaAssert(n >= 0, @"Negative lines to offsetOfWrappedLineInBuffer");
    if (_mayHaveDoubleWidthCharacter) {
        if (!metadata->double_width_characters ||
            metadata->width_for_double_width_characters_cache != width) {
            [self populateDoubleWidthCharacterCacheInMetadata:metadata buffer:p length:length width:width];
        }

        __block int lines = 0;
        __block int i = 0;
        __block NSUInteger lastIndex = 0;
        [metadata->double_width_characters enumerateIndexesInRange:NSMakeRange(0, MAX(0, n + 1))
                                                           options:0
                                                        usingBlock:^(NSUInteger indexOfLineThatWouldStartWithRightHalf, BOOL * _Nonnull stop) {
            int numberOfLines = indexOfLineThatWouldStartWithRightHalf - lastIndex;
            lines += numberOfLines;
            i += width * numberOfLines;
            i--;
            lastIndex = indexOfLineThatWouldStartWithRightHalf;
        }];
        if (lines < n) {
            i += (n - lines) * width;
        }
        return i;
    } else {
        return n * width;
    }
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
                         lineOffset:&lineOffset];
    iTermMetadata result;
    iTermMetadataInitCopyingSubrange(&result, (iTermImmutableMetadata *)&metadata, lineOffset, width);
    iTermMetadataAutorelease(result);
    return iTermMetadataMakeImmutable(result);
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

- (const screen_char_t *)_wrappedLineWithWrapWidth:(int)width
                                          location:(LineBlockLocation)location
                                           lineNum:(int*)lineNum
                                        lineLength:(int*)lineLength
                                 includesEndOfLine:(int*)includesEndOfLine
                                           yOffset:(int*)yOffsetPtr
                                      continuation:(screen_char_t *)continuationPtr
                              isStartOfWrappedLine:(BOOL *)isStartOfWrappedLine
                                          metadata:(out iTermImmutableMetadata *)metadataPtr
                                        lineOffset:(out int *)lineOffset {
    int offset;
    if (gEnableDoubleWidthCharacterLineCache) {
        offset = [self offsetOfWrappedLineInBuffer:buffer_start + location.prev
                                 wrappedLineNumber:*lineNum
                                      bufferLength:location.length
                                             width:width
                                          metadata:&metadata_[location.index]];
    } else {
        offset = OffsetOfWrappedLine(buffer_start + location.prev,
                                     *lineNum,
                                     location.length,
                                     width,
                                     _mayHaveDoubleWidthCharacter);
    }

    *lineNum = 0;
    // offset: the relevant part of the raw line begins at this offset into it
    *lineLength = location.length - offset;  // the length of the suffix of the raw line, beginning at the wrapped line we want
    if (*lineLength > width) {
        // return an infix of the full line
        if (width > 1 && ScreenCharIsDWC_RIGHT(buffer_start[location.prev + offset + width])) {
            // Result would end with the first half of a double-width character
            *lineLength = width - 1;
            *includesEndOfLine = EOL_DWC;
        } else {
            *lineLength = width;
            *includesEndOfLine = EOL_SOFT;
        }
    } else {
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
    if (continuationPtr) {
        *continuationPtr = metadata_[location.index].continuation;
        continuationPtr->code = *includesEndOfLine;
    }
    if (isStartOfWrappedLine) {
        *isStartOfWrappedLine = (offset == 0);
    }
    if (metadataPtr) {
        iTermMetadataRetainAutorelease(metadata_[location.index].lineMetadata);
        *metadataPtr = iTermMetadataMakeImmutable(metadata_[location.index].lineMetadata);
    }
    if (lineOffset) {
        *lineOffset = offset;
    }
    return buffer_start + location.prev + offset;
}

- (LineBlockLocation)locationOfRawLineForWidth:(int)width
                                       lineNum:(int *)lineNum {
    ITBetaAssert(*lineNum >= 0, @"Negative lines to getWrappedLineWithWrapWidth");
    int prev = 0;
    int numEmptyLines = 0;
    for (int i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        const int length = cll - prev;
        if (*lineNum > 0) {
            if (length == 0) {
                ++numEmptyLines;
            } else {
                numEmptyLines = 0;
            }
        } else if (length == 0 && cumulative_line_lengths[i] > start_offset) {
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
            //   Then the location for the start of line 1 is (prev=0,numEmptyLines=1,index=1,length=0)
            // 2. Given:
            //    (empty)
            //    (empty)
            //   Then the location for the start of line 1 is (prev=0,numEmptyLines=1,index=1,length=0)
            ++numEmptyLines;
        }
        int spans;
        const BOOL useCache = gUseCachingNumberOfLines;
        if (useCache && _mayHaveDoubleWidthCharacter) {
            LineBlockMetadata *metadata = &metadata_[i];
            if (metadata->width_for_number_of_wrapped_lines == width &&
                metadata->number_of_wrapped_lines > 0) {
                spans = metadata->number_of_wrapped_lines;
            } else {
                spans = [self numberOfFullLinesFromOffset:(buffer_start - raw_buffer) + prev
                                                   length:length
                                                    width:width];
                metadata->number_of_wrapped_lines = spans;
                metadata->width_for_number_of_wrapped_lines = width;
             }
        } else {
            spans = [self numberOfFullLinesFromOffset:(buffer_start - raw_buffer) + prev
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
            // eat up *lineNum many width-sized wrapped lines from this start of the current full line
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
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:lineNum];
    if (!location.found) {
        return NULL;
    }
    // We found the raw line that includes the wrapped line we're searching for.
    // eat up *lineNum many width-sized wrapped lines from this start of the current full line
    return [self _wrappedLineWithWrapWidth:width
                                  location:location
                                   lineNum:lineNum
                                lineLength:lineLength
                         includesEndOfLine:includesEndOfLine
                                   yOffset:yOffsetPtr
                              continuation:continuationPtr
                      isStartOfWrappedLine:isStartOfWrappedLine
                                  metadata:metadataPtr
                                lineOffset:NULL];
}

- (ScreenCharArray *)rawLineAtWrappedLineOffset:(int)lineNum width:(int)width {
    int temp = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&temp];
    if (!location.found) {
        return NULL;
    }
    const screen_char_t *buffer = buffer_start + location.prev;
    const int length = location.length;
    screen_char_t continuation = { 0 };
    if (is_partial && location.index + 1 == cll_entries) {
        continuation.code = EOL_SOFT;
    } else {
        continuation.code = EOL_HARD;
    }
    return [[ScreenCharArray alloc] initWithLine:buffer
                                          length:length
                                    continuation:continuation];
}

- (iTermImmutableMetadata)metadataForRawLineAtWrappedLineOffset:(int)lineNum width:(int)width {
    int temp = lineNum;
    const LineBlockLocation location = [self locationOfRawLineForWidth:width lineNum:&temp];
    if (!location.found) {
        return iTermImmutableMetadataDefault();
    }

    iTermMetadataRetainAutorelease(metadata_[location.index].lineMetadata);
    return iTermMetadataMakeImmutable(metadata_[location.index].lineMetadata);
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
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        int length = cll - prev;
        const int marginalLines = [self numberOfFullLinesFromOffset:(buffer_start - raw_buffer) + prev
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

- (BOOL) hasCachedNumLinesForWidth: (int) width {
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
    if (cll_entries == first_entry) {
        return;
    }
    cll_entries -= 1;
    is_partial = NO;
    if (cll_entries == first_entry) {
        // Popped the last line. Reset everything.
        buffer_start = raw_buffer;
        start_offset = 0;
        first_entry = 0;
        cll_entries = 0;
    }
    // refresh cache
    metadata_[cll_entries].number_of_wrapped_lines = 0;
    if (gEnableDoubleWidthCharacterLineCache) {
        metadata_[cll_entries].double_width_characters = nil;
        iTermMetadataSetExternalAttributes(&metadata_[cll_entries].lineMetadata, nil);
    }
    cached_numlines_width = -1;
    iTermLineBlockDidChange(self);
}

- (BOOL)popLastLineInto:(screen_char_t const **)ptr
             withLength:(int *)length
              upToWidth:(int)width
               metadata:(out iTermImmutableMetadata *)metadataPtr
           continuation:(screen_char_t *)continuationPtr {
    NSNumber *number =
    [self modifyWithBlock:^id(id<iTermLineBlockMutationCertificate> cert) {
        const BOOL result = [self reallyPopLastLineInto:ptr
                                             withLength:length
                                              upToWidth:width
                                               metadata:metadataPtr
                                           continuation:continuationPtr
                                                   cert:cert];
        return @(result);
    }];
    return number.boolValue;
}

- (BOOL)reallyPopLastLineInto:(screen_char_t const **)ptr
                   withLength:(int *)length
                    upToWidth:(int)width
                     metadata:(out iTermImmutableMetadata *)metadataPtr
                 continuation:(screen_char_t *)continuationPtr
                         cert:(id<iTermLineBlockMutationCertificate>)cert {
    if (cll_entries == first_entry) {
        // There is no last line to pop.
        return NO;
    }
    _numberOfFullLinesCache.clear();
    int start;
    if (cll_entries == first_entry + 1) {
        start = 0;
    } else {
        start = cumulative_line_lengths[cll_entries - 2] - start_offset;
    }
    if (continuationPtr) {
        *continuationPtr = metadata_[cll_entries - 1].continuation;
    }

    const int end = cumulative_line_lengths[cll_entries - 1] - start_offset;
    const int available_len = end - start;
    if (available_len > width) {
        // The last raw line is longer than width. So get the last part of it after wrapping.
        // If the width is four and the last line is "0123456789" then return "89". It would
        // wrap as: 0123/4567/89. If there are double-width characters, this ensures they are
        // not split across lines when computing the wrapping.
        const int numLines = [self numberOfFullLinesFromOffset:(buffer_start - raw_buffer) + start
                                                        length:available_len
                                                         width:width];
        int offset_from_start = OffsetOfWrappedLine(buffer_start + start,
                                                    numLines,
                                                    available_len,
                                                    width,
                                                    _mayHaveDoubleWidthCharacter);
        *length = available_len - offset_from_start;
        if (ptr) {
            *ptr = buffer_start + start + offset_from_start;
        }
        cert.mutableCumulativeLineLengths[cll_entries - 1] -= *length;
        metadata_[cll_entries - 1].number_of_wrapped_lines = 0;
        if (gEnableDoubleWidthCharacterLineCache) {
            metadata_[cll_entries - 1].double_width_characters = nil;
        }
        iTermExternalAttributeIndex *attrs = iTermMetadataGetExternalAttributesIndex(metadata_[cll_entries - 1].lineMetadata);
        const int split_index = available_len - *length;
        if (metadataPtr) {
            iTermMetadata metadata = metadata_[cll_entries - 1].lineMetadata;
            iTermMetadataRetain(metadata);
            iTermMetadataSetExternalAttributes(&metadata, [attrs subAttributesFromIndex:split_index]);
            *metadataPtr = iTermMetadataMakeImmutable(metadata);
            iTermMetadataAutorelease(metadata);
        }
        iTermExternalAttributeIndex *prefix = [attrs subAttributesToIndex:split_index];
        iTermMetadataSetExternalAttributes(&metadata_[cll_entries - 1].lineMetadata,
                                           prefix);

        is_partial = YES;
    } else {
        // The last raw line is not longer than width. Return the whole thing.
        *length = available_len;
        if (ptr) {
            *ptr = buffer_start + start;
        }
        if (metadataPtr) {
            iTermMetadata metadata = metadata_[cll_entries - 1].lineMetadata;
            iTermMetadataRetainAutorelease(metadata);
            *metadataPtr = iTermMetadataMakeImmutable(metadata);
        }
        --cll_entries;
        is_partial = NO;
    }

    if (cll_entries == first_entry) {
        // Popped the last line. Reset everything.
        buffer_start = raw_buffer;
        start_offset = 0;
        first_entry = 0;
        cll_entries = 0;
    }
    // refresh cache
    cached_numlines_width = -1;
    iTermLineBlockDidChange(self);
    return YES;
}

- (BOOL)isEmpty
{
    return cll_entries == first_entry;
}

- (BOOL)allLinesAreEmpty {
    if (self.isEmpty) {
        return YES;
    }
    return (cumulative_line_lengths[cll_entries - 1] == start_offset);
}

- (int)numRawLines
{
    return cll_entries - first_entry;
}

- (int)numEntries
{
    return cll_entries;
}

- (int)startOffset
{
    return start_offset;
}

- (int)lengthOfLastLine {
    if ([self numRawLines] == 0) {
        return 0;
    }
    const int index = cll_entries - 1;
    return [self getRawLineLength:index];
}

- (int)getRawLineLength:(int)linenum
{
    ITAssertWithMessage(linenum < cll_entries && linenum >= 0, @"Out of bounds");
    int prev;
    if (linenum == 0) {
        prev = 0;
    } else {
        prev = cumulative_line_lengths[linenum-1] - start_offset;
    }
    return cumulative_line_lengths[linenum] - start_offset - prev;
}

- (const screen_char_t*)rawLine:(int)linenum {
    int start;
    if (linenum == 0) {
        start = 0;
    } else {
        start = cumulative_line_lengths[linenum - 1];
    }
    return raw_buffer + start;
}

- (void)changeBufferSize:(int)capacity {
    [self modifyWithBlock:^id(id<iTermLineBlockMutationCertificate> cert) {
        [self changeBufferSize:capacity cert:cert];
        return nil;
    }];
}

- (void)changeBufferSize:(int)capacity cert:(id<iTermLineBlockMutationCertificate>)cert {
    ITAssertWithMessage(capacity >= [self rawSpaceUsed], @"Truncating used space");
    capacity = MAX(1, capacity);
    [cert setRawBufferCapacity:capacity];
    buffer_start = raw_buffer + start_offset;
    buffer_size = capacity;
    cached_numlines_width = -1;
}

- (int)rawBufferSize
{
    return buffer_size;
}

- (BOOL)hasPartial
{
    return is_partial;
}

- (void)setPartial:(BOOL)partial {
    if (partial == is_partial) {
        return;
    }
    is_partial = partial;
    iTermLineBlockDidChange(self);
}

- (void)shrinkToFit {
    [self modifyWithBlock:^id(id<iTermLineBlockMutationCertificate> cert) {
        [self changeBufferSize:[self rawSpaceUsed] cert:cert];
        return nil;
    }];
}

- (int)dropLines:(int)orig_n withWidth:(int)width chars:(int *)charsDropped {
    int n = orig_n;
    int prev = 0;
    int length;
    int i;
    *charsDropped = 0;
    int initialOffset = start_offset;
    _numberOfFullLinesCache.clear();
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        LineBlockMetadata *metadata = &metadata_[i];
        length = cll - prev;
        // Get the number of full-length wrapped lines in this raw line. If there
        // were only single-width characters the formula would be:
        //     (length - 1) / width;
        int spans = [self numberOfFullLinesFromOffset:(buffer_start - raw_buffer) + prev
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
            int offset = OffsetOfWrappedLine(buffer_start + prev,
                                             n,
                                             length,
                                             width,
                                             _mayHaveDoubleWidthCharacter);
            if (width != cached_numlines_width) {
                cached_numlines_width = -1;
            } else {
                cached_numlines -= orig_n;
            }
            buffer_start += prev + offset;
            start_offset = buffer_start - raw_buffer;
            first_entry = i;
            metadata->number_of_wrapped_lines = 0;
            if (gEnableDoubleWidthCharacterLineCache) {
                metadata_[i].double_width_characters = nil;
            }
            iTermMetadataSetExternalAttributes(&metadata_[i].lineMetadata, nil);

            *charsDropped = start_offset - initialOffset;

#ifdef TEST_LINEBUFFER_SANITY
            [self checkAndResetCachedNumlines:"dropLines" width: width];
#endif
            iTermLineBlockDidChange(self);
            return orig_n;
        }
        prev = cll;
    }

    // Consumed the whole buffer.
    cached_numlines_width = -1;
    cll_entries = 0;
    buffer_start = raw_buffer;
    start_offset = 0;
    first_entry = 0;
    *charsDropped = [self rawSpaceUsed];
    iTermLineBlockDidChange(self);
    return orig_n - n;
}

- (void)dropMirroringProgenitor:(LineBlock *)other {
    assert(_progenitor == other);
    assert(self.owner == nil || self.owner == other);
    assert(cll_capacity <= other->cll_capacity);

    if (start_offset == other->start_offset &&
        first_entry == other->first_entry) {
        DLog(@"No change");
        return;
    }

    DLog(@"start_offset %@ -> %@", @(start_offset), @(other->start_offset));
    start_offset = other->start_offset;
    buffer_start = raw_buffer + start_offset;
    cached_numlines_width = -1;

    while (first_entry < other->first_entry && first_entry < cll_capacity) {
        if (gEnableDoubleWidthCharacterLineCache) {
            metadata_[first_entry].double_width_characters = nil;
        }
        DLog(@"Drop entry");
        iTermMetadataSetExternalAttributes(&metadata_[first_entry].lineMetadata, nil);
        first_entry += 1;
    }
#ifdef TEST_LINEBUFFER_SANITY
    [self checkAndResetCachedNumlines:"dropLines" width: width];
#endif
    iTermLineBlockDidChange(self);
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

- (int) _lineRawOffset: (int) anIndex
{
    if (anIndex == first_entry) {
        return start_offset;
    } else {
        return cumulative_line_lengths[anIndex - 1];
    }
}

static NSString* RewrittenRegex(NSString* originalRegex) {
    // Convert ^ in a context where it refers to the start of string to kPrefixChar
    // Convert $ in a context where it refers to the end of string to kSuffixChar
    // ^ is NOT start-of-string when:
    //   - it is escaped
    //   - it is preceded by an unescaped [
    //   - it is preceded by an unescaped [:
    // $ is NOT end-of-string when:
    //   - it is escaped
    //
    // It might be possible to write this as a regular substitution but it would be a crazy mess.

    NSMutableString* rewritten = [NSMutableString stringWithCapacity:[originalRegex length]];
    BOOL escaped = NO;
    BOOL inSet = NO;
    BOOL firstCharInSet = NO;
    unichar prevChar = 0;
    for (int i = 0; i < [originalRegex length]; i++) {
        BOOL nextCharIsFirstInSet = NO;
        unichar c = [originalRegex characterAtIndex:i];
        switch (c) {
            case '\\':
                escaped = !escaped;
                break;

            case '[':
                if (!inSet && !escaped) {
                    inSet = YES;
                    nextCharIsFirstInSet = YES;
                }
                break;

            case ']':
                if (inSet && !escaped) {
                    inSet = NO;
                }
                break;

            case ':':
                if (inSet && firstCharInSet && prevChar == '[') {
                    nextCharIsFirstInSet = YES;
                }
                break;

            case '^':
                if (!escaped && !firstCharInSet) {
                    c = kPrefixChar;
                }
                break;

            case '$':
                if (!escaped) {
                    c = kSuffixChar;
                }
                break;
        }
        prevChar = c;
        firstCharInSet = nextCharIsFirstInSet;
        [rewritten appendFormat:@"%C", c];
    }

    return rewritten;
}

// Returns the index into rawline that a result was found.
// Fills in *resultLength with the number of screen_char_t's the result spans.
// Fills in *rangeOut with the range of haystack/charHaystack where the result was found.
static int CoreSearch(NSString *needle,
                      const screen_char_t *rawline,
                      int raw_line_length,
                      int start,
                      int end,
                      FindOptions options,
                      iTermFindMode mode,
                      int *resultLength,
                      NSString *entireHaystack,
                      NSRange haystackRange,
                      unichar *charHaystack,
                      const int *deltas,
                      int deltaOffset,
                      NSRange *rangeOut) {
    RKLRegexOptions apiOptions = RKLNoOptions;
    NSRange range;
    const BOOL regex = (mode == iTermFindModeCaseInsensitiveRegex ||
                        mode == iTermFindModeCaseSensitiveRegex);
    if (regex) {
        BOOL backwards = NO;
        if (options & FindOptBackwards) {
            backwards = YES;
        }
        if (mode == iTermFindModeCaseInsensitiveRegex) {
            apiOptions = static_cast<RKLRegexOptions>(apiOptions | RKLCaseless);
        }

        NSError* regexError = nil;
        NSRange temp;
        NSString* rewrittenRegex = RewrittenRegex(needle);
        // TODO: This is grossly inefficient. If you have a short needle and a long haystack this is done many times per raw line.
        NSString *haystack = [entireHaystack substringWithRange:haystackRange];
        NSString* sanitizedHaystack = [haystack stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%c", kPrefixChar]
                                                                          withString:[NSString stringWithFormat:@"%c", IMPOSSIBLE_CHAR]];
        sanitizedHaystack = [sanitizedHaystack stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%c", kSuffixChar]
                                                                         withString:[NSString stringWithFormat:@"%c", IMPOSSIBLE_CHAR]];

        NSString* sandwich;
        BOOL hasPrefix = YES;
        BOOL hasSuffix = YES;
        if (end == raw_line_length) {
            if (start == 0) {
                sandwich = [NSString stringWithFormat:@"%C%@%C", kPrefixChar, sanitizedHaystack, kSuffixChar];
            } else {
                hasPrefix = NO;
                sandwich = [NSString stringWithFormat:@"%@%C", sanitizedHaystack, kSuffixChar];
            }
        } else {
            hasSuffix = NO;
            sandwich = [NSString stringWithFormat:@"%C%@", kPrefixChar, sanitizedHaystack];
        }

        // TODO: RegexKitLite is grossly inefficient. It compiles the regex each and every time. Use NSRegularExpression instead.
        // Also in the backwards code below.
        temp = [sandwich rangeOfRegex:rewrittenRegex
                              options:apiOptions
                              inRange:NSMakeRange(0, [sandwich length])
                              capture:0
                                error:&regexError];
        range = temp;

        if (backwards) {
            int locationAdjustment = hasSuffix ? 1 : 0;
            // keep searching from one char after the start of the match until we don't find anything.
            // regexes aren't good at searching backwards.
            while (!regexError && temp.location != NSNotFound && temp.location+locationAdjustment < [sandwich length]) {
                if (temp.length != 0) {
                    range = temp;
                }
                temp.location += MAX(1, temp.length);
                temp = [sandwich rangeOfRegex:rewrittenRegex
                                      options:apiOptions
                                      inRange:NSMakeRange(temp.location, [sandwich length] - temp.location)
                                      capture:0
                                        error:&regexError];
            }
        }
        if (range.length == 0) {
            range.location = NSNotFound;
        }
        if (!regexError && range.location != NSNotFound) {
            if (hasSuffix && range.location + range.length == [sandwich length]) {
                // match includes $
                if (range.length > 0) {
                    --range.length;
                }
                if (range.length == 0 && range.location > 0) {
                    // matched only on $
                    --range.location;
                }
            }
            if (hasPrefix && range.location == 0) {
                if (range.length > 0) {
                    --range.length;
                }
            } else if (hasPrefix) {
                if (range.location > 0) {
                    --range.location;
                }
            }
        }
        if (range.length <= 0) {
            // match on ^ or $
            range.location = NSNotFound;
        }
        if (regexError) {
            VLog(@"regex error: %@", regexError);
            range.length = 0;
            range.location = NSNotFound;
        }
    } else {
        // Substring (not regex)
        if (options & FindOptBackwards) {
            apiOptions = static_cast<RKLRegexOptions>(apiOptions | NSBackwardsSearch);
        }
        BOOL caseInsensitive = (mode == iTermFindModeCaseInsensitiveSubstring);
        if (mode == iTermFindModeSmartCaseSensitivity &&
            [needle rangeOfCharacterFromSet:[NSCharacterSet uppercaseLetterCharacterSet]].location == NSNotFound) {
            caseInsensitive = YES;
        }
        if (caseInsensitive) {
            apiOptions = static_cast<RKLRegexOptions>(apiOptions | NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch);
        }
        if ((options & FindOptEmptyQueryMatches) == FindOptEmptyQueryMatches && needle.length == 0) {
            range = NSMakeRange(0, 0);
        } else {
            SearchLog(@"Search subrange %@ of haystack %@", NSStringFromRange(haystackRange), [entireHaystack asciified]);
            const NSRange foundRange = [entireHaystack rangeOfString:needle options:apiOptions range:haystackRange];
            if (foundRange.location == NSNotFound) {
                range = foundRange;
            } else {
                SearchLog(@"Searched %@ and found %@ at %@. Suffix from start of range is: %@", entireHaystack, needle, NSStringFromRange(foundRange), [entireHaystack substringFromIndex:foundRange.location]);
                // `range` needs to be relative to `haystackRange`.
                range = NSMakeRange(foundRange.location - haystackRange.location,
                                    foundRange.length);
                SearchLog(@"haystack-relative range is %@", NSStringFromRange(range));
            }
        }
    }
    int result = -1;
    if (range.location != NSNotFound) {
        // Convert range to locations in the full raw buffer.
        const int adjustedLocation = range.location + haystackRange.location + deltas[range.location];
        SearchLog(@"adjustedLocation(%@) = range.location(%@) + haystackRange.location(%@) + deltas[range.location](%@)",
              @(adjustedLocation), @(range.location), @(haystackRange.location), @(deltas[range.location]));

        const int adjustedLength = range.length + deltas[MAX(range.location, NSMaxRange(range) - 1)] - deltas[range.location];
        SearchLog(@"adjustedLength(%@) = range.length(%@) + deltas[range.upperBound](%@) - deltas[range.location](%@)",
              @(adjustedLength), @(range.length), @(deltas[NSMaxRange(range)]), @(deltas[range.location]));
        *resultLength = adjustedLength;
        result = adjustedLocation;
    }
    if (rangeOut) {
        *rangeOut = range;
    }
    return result;
}

// This may return a value for the next cell if `cellOffset` points at something without a corresponding
// code point, such as a DWC_RIGHT.
static int UTF16OffsetFromCellOffset(int cellOffset,  // search for utf-16 offset with this cell offset
                                     const int *deltas,  // indexed by code point
                                     int numCodePoints) {
    // `deltas[i] + i` gives the cell offset for UTF-16 offset `i`.
    // Example:
    //
    //         0  1  2  3  4  5  6  7  8  9  A
    // cells   a  b  -  c  -  d  e  -  f  g
    // utf-16  a  b  c  d  +  +  e  f  +  +  g         // + means combining mark
    // deltas  0  0  1  2  1  0  0  1  0 -1 -1
    //
    // An index `i` into utf-16 can be converted to an index into cells by adding `deltas[i]`.
    // To go in reverse is more difficult. Starting with an index in cells doesn't give you a
    // clue where to look in deltas. There can easily be more cells than deltas (e.g., lots of
    // DWCs and no combining marks).
    //
    // You could do a binary search but I haven't implemented it yet because it
    // adds risk and this is fast enough.
    for (int utf16Index = 0; utf16Index < numCodePoints; utf16Index++) {
        const int cellIndex = utf16Index + deltas[utf16Index];
        if (cellIndex >= cellOffset) {
            return utf16Index;
        }
    }
    return numCodePoints;
}

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

- (void)_findInRawLine:(int)entry
                needle:(NSString*)needle
               options:(FindOptions)options
                  mode:(iTermFindMode)mode
                  skip:(int)skip
                length:(int)raw_line_length
       multipleResults:(BOOL)multipleResults
               results:(NSMutableArray *)results {
    const screen_char_t *rawline = raw_buffer + [self _lineRawOffset:entry];
    if (skip > raw_line_length) {
        skip = raw_line_length;
    }
    if (skip < 0) {
        skip = 0;
    }

    NSString *haystack;
    unichar *charHaystack;
    int *deltas;
    haystack = ScreenCharArrayToString(rawline,
                                       0,
                                       raw_line_length,
                                       &charHaystack,
                                       &deltas);

#ifdef DEBUG_SEARCH
    SearchLog(@"Searching rawline %@", [self prettyRawLine:rawline length:raw_line_length]);
    SearchLog(@"Deltas: %@", [self prettyDeltas:deltas length:haystack.length]);
#endif

    if (options & FindOptBackwards) {
        // This algorithm is wacky and slow but stay with me here:
        // When you search backward, the most common case is that you are
        // repeating the previous search but with a one-character longer
        // needle (having grown at the end). So the rightmost result we can
        // accept is one whose leftmost position is at the leftmost position of
        // the previous result.
        //
        // Example: Consider a previous search of [jump]
        //  The quick brown fox jumps over the lazy dog.
        //                      ^^^^
        // The search is then extended to [jumps]. We want to return:
        //  The quick brown fox jumps over the lazy dog.
        //                      ^^^^^
        // Ideally, we would search only the necessary part of the haystack:
        //  Search("The quick brown fox jumps", "jumps")
        //
        // But what we did there was to add one byte to the haystack. That works
        // for ascii, but not in other cases. Let us consider a localized
        // German search where "ss" matches "ß". Let's first search for [jump]
        // in this translation:
        //
        //  Ein quicken Braunfox jumpss uber die Lazydog.
        //                       ^^^^
        // Then the needle becomes [jumpß]. Under the previous algorithm we'd
        // extend the haystack to:
        //  Ein quicken Braunfox jumps
        // And there is no match for jumpß.
        //
        // So to do the optimal algorithm, you'd have to know how many characters
        // to add to the haystack in the worst localized case. With decomposed
        // diacriticals, the upper bound is unclear.
        //
        // I'm going to err on the side of correctness over performance. I'm
        // sure this could be improved if needed. One obvious
        // approach is to use the naïve algorithm when the text is all ASCII.
        //
        // Thus, the algorithm is to do a reverse search until a hit is found
        // that begins not before 'skip', which is the leftmost acceptable
        // position.

        int limit = raw_line_length;
        int tempResultLength = 0;
        int tempPosition;

        int numUnichars = [haystack length];
        const unsigned long long kMaxSaneStringLength = 1000000000LL;
        NSRange previousRange = NSMakeRange(NSNotFound, 0);
        do {
            haystack = CharArrayToString(charHaystack, numUnichars);
            if ([haystack length] >= kMaxSaneStringLength) {
                // There's a bug in OS 10.9.0 (and possibly other versions) where the string
                // @"a⃑" reports a length of 0x7fffffffffffffff, which causes this loop to never
                // terminate.
                break;
            }
            tempPosition = CoreSearch(needle,
                                      rawline,
                                      raw_line_length, 0,
                                      limit,
                                      options,
                                      mode,
                                      &tempResultLength,
                                      haystack,
                                      NSMakeRange(0, haystack.length),
                                      charHaystack,
                                      deltas,
                                      0,
                                      NULL);

            limit = tempPosition + tempResultLength - 1;
            // find i so that i-deltas[i] == limit
            while (numUnichars >= 0 && numUnichars + deltas[numUnichars] > limit) {
                --numUnichars;
            }
            NSRange range = NSMakeRange(tempPosition, tempResultLength);
            if (tempPosition != -1 &&
                tempPosition <= skip &&
                !NSEqualRanges(NSIntersectionRange(range, previousRange), range)) {
                previousRange = range;
                ResultRange *r = [[ResultRange alloc] init];
                r->position = tempPosition;
                r->length = tempResultLength;
                [results addObject:r];
            }
        } while (tempPosition != -1 && (multipleResults || tempPosition > skip));
    } else {
        // Search forward
        NSRange resultRange = NSMakeRange(UTF16OffsetFromCellOffset(skip, deltas, raw_line_length), 0);
        while (skip < raw_line_length) {
            const NSInteger codePointsToSkip = NSMaxRange(resultRange);
            int tempResultLength = 0;
            NSRange relativeResultRange = NSMakeRange(0, 0);
#ifdef DEBUG_SEARCH
            const int savedSkip = skip;
#endif
            // tempPosition and tempResultLength are indexes into rawline
            // deltas is indexed by indexes into NSString.
            int tempPosition = CoreSearch(needle,
                                          rawline,
                                          raw_line_length,
                                          skip,  // treated as index into rawline
                                          raw_line_length,
                                          options,
                                          mode,
                                          &tempResultLength,
                                          haystack,
                                          NSMakeRange(codePointsToSkip, haystack.length - codePointsToSkip),
                                          charHaystack + codePointsToSkip,
                                          deltas + codePointsToSkip,
                                          deltas[codePointsToSkip],
                                          &relativeResultRange);
            resultRange = NSMakeRange(relativeResultRange.location + codePointsToSkip,
                                      relativeResultRange.length);
            if (tempPosition != -1) {
                ResultRange *r = [[ResultRange alloc] init];
                r->position = tempPosition;
                r->length = tempResultLength;
                SearchLog(@"Got result %@ in %@", r, [haystack asciified]);
                [results addObject:r];
                if (!multipleResults) {
                    break;
                }
                assert(tempResultLength >= 0);
                assert(tempPosition <= raw_line_length);
                skip = tempPosition + tempResultLength;
                assert(skip >= 0);
#ifdef DEBUG_SEARCH
                if (skip < 0) {
                    skip = savedSkip;
                    int tempPosition = CoreSearch(needle,
                                                  rawline,
                                                  raw_line_length,
                                                  skip,
                                                  raw_line_length,
                                                  options,
                                                  mode,
                                                  &tempResultLength,
                                                  haystack,
                                                  NSMakeRange(codePointsToSkip, haystack.length - codePointsToSkip),
                                                  charHaystack + codePointsToSkip,
                                                  deltas + skip,
                                                  deltas[skip],
                                                  &relativeResultRange);
                    skip = tempPosition + tempResultLength;
                    assert(skip >= 0);
                }
#endif
                if (options & FindOneResultPerRawLine) {
                    break;
                }
            } else {
                break;
            }
        }
    }
    free(deltas);
    free(charHaystack);
}

- (int) _lineLength: (int) anIndex
{
    int prev;
    if (anIndex == first_entry) {
        prev = start_offset;
    } else {
        prev = cumulative_line_lengths[anIndex - 1];
    }
    return cumulative_line_lengths[anIndex] - prev;
}

- (int) _findEntryBeforeOffset: (int) offset
{
    if (offset < start_offset) {
        return -1;
    }

    int i;
    for (i = first_entry; i < cll_entries; ++i) {
        if (cumulative_line_lengths[i] > offset) {
            return i;
        }
    }
    return -1;
}

- (void)findSubstring:(NSString*)substring
              options:(FindOptions)options
                 mode:(iTermFindMode)mode
             atOffset:(int)offset
              results:(NSMutableArray *)results
      multipleResults:(BOOL)multipleResults
includesPartialLastLine:(BOOL *)includesPartialLastLine {
    *includesPartialLastLine = NO;
    if (offset == -1) {
        offset = [self rawSpaceUsed] - 1;
    }
    int entry;
    int limit;
    int dir;
    if (options & FindOptBackwards) {
        entry = [self _findEntryBeforeOffset: offset];
        if (entry == -1) {
            // Maybe there were no lines or offset was <= start_offset.
            return;
        }
        limit = first_entry - 1;
        dir = -1;
    } else {
        entry = first_entry;
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
        static const int MAX_SEARCHABLE_LINE_LENGTH = 500000;
        [self _findInRawLine:entry
                      needle:substring
                     options:options
                        mode:mode
                        skip:skipped
                      length:MIN(MAX_SEARCHABLE_LINE_LENGTH, [self _lineLength: entry])
             multipleResults:multipleResults
                     results:newResults];
        for (ResultRange* r in newResults) {
            r->position += line_raw_offset;
            [results addObject:r];
        }
        if (newResults.count && is_partial && entry + 1 == cll_entries) {
            *includesPartialLastLine = YES;
        }
        if ([newResults count] && !multipleResults) {
            return;
        }
        entry += dir;
    }
}

// Returns YES if the position is valid for this block.
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
    int prev = start_offset;
    for (i = first_entry; i < cll_entries; ++i) {
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
            // the following call to iTermLineBlockNumberOfFullLinesImpl.

            if (bytes_to_consume_in_this_line < line_length &&
                prev + bytes_to_consume_in_this_line + 1 < eol) {
                assert(prev + bytes_to_consume_in_this_line + 1 < buffer_size);
                if (width > 1 && ScreenCharIsDWC_RIGHT(raw_buffer[prev + bytes_to_consume_in_this_line + 1])) {
                    ++dwc_peek;
                }
            }
            int consume = [self numberOfFullLinesFromOffset:prev
                                                     length:MIN(line_length, bytes_to_consume_in_this_line + 1 + dwc_peek)
                                                      width:width];
            *y += consume;
            if (consume > 0) {
                // Offset from prev where the consume'th line begin.
                int offset = OffsetOfWrappedLine(raw_buffer + prev,
                                                 consume,
                                                 line_length,
                                                 width,
                                                 _mayHaveDoubleWidthCharacter);
                // We know that position falls in this line. Set x to the number
                // of chars after the beginning on the line. If there were only
                // single-width chars the formula would be:
                //     bytes_to_consume_in_this_line % (consume * width);
                *x = position - (prev + offset);
            } else {
                *x = bytes_to_consume_in_this_line;
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
    NSMutableArray *metadataArray = [NSMutableArray array];
    for (int i = 0; i < cll_entries; i++) {
        [metadataArray addObject:[@[ @(metadata_[i].continuation.code),
                                     @(metadata_[i].continuation.backgroundColor),
                                     @(metadata_[i].continuation.bgGreen),
                                     @(metadata_[i].continuation.bgBlue),
                                     @(metadata_[i].continuation.backgroundColorMode) ]
                                  arrayByAddingObjectsFromArray:iTermMetadataEncodeToArray(metadata_[i].lineMetadata)]];
    }
    return metadataArray;
}

- (NSDictionary *)dictionary {
    NSData *rawBufferData = [NSData dataWithBytes:raw_buffer
                                           length:[self rawSpaceUsed] * sizeof(screen_char_t)];
    return @{ kLineBlockRawBufferV3Key: rawBufferData,
              kLineBlockBufferStartOffsetKey: @(buffer_start - raw_buffer),
              kLineBlockStartOffsetKey: @(start_offset),
              kLineBlockFirstEntryKey: @(first_entry),
              kLineBlockBufferSizeKey: @(buffer_size),
              kLineBlockCLLKey: [self cumulativeLineLengthsArray],
              kLineBlockIsPartialKey: @(is_partial),
              kLineBlockMetadataKey: [self metadataArray],
              kLineBlockMayHaveDWCKey: @(_mayHaveDoubleWidthCharacter),
              kLineBlockGuid: _guid };
}

- (int)numberOfCharacters {
    return self.rawSpaceUsed - start_offset;
}

- (int)lengthOfLine:(int)lineNumber {
    if (lineNumber == 0) {
        return cumulative_line_lengths[0];
    } else {
        return cumulative_line_lengths[lineNumber] - cumulative_line_lengths[lineNumber - 1];
    }
}

- (int)numberOfTrailingEmptyLines {
    int count = 0;
    for (int i = cll_entries - 1; i >= first_entry; i--) {
        if ([self lengthOfLine:i] == 0) {
            count++;
        } else {
            break;
        }
    }
    return count;
}

- (int)numberOfLeadingEmptyLines {
    int count = 0;
    for (int i = first_entry; i < cll_entries; i++) {
        if ([self lengthOfLine:i] == 0) {
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
    return cumulative_line_lengths[cll_entries - 1] > start_offset;
}

- (void)addObserver:(id<iTermLineBlockObserver>)observer {
    [_observers addObject:[iTermWeakBox boxFor:observer]];
}

- (void)removeObserver:(id<iTermLineBlockObserver>)observer {
    [_observers removeObjectsPassingTest:^BOOL(iTermWeakBox<id<iTermLineBlockObserver>> *anObject) {
        return anObject.object == nil || anObject.object == observer;
    }];
}

- (BOOL)hasObserver:(id<iTermLineBlockObserver>)observer {
    // Can't use -[NSArray containsObject:] because it does [observer isEqual:_observers[j]] where
    // _observesr[j] is an iTermWeakBox.
    return [_observers anyWithBlock:^BOOL(iTermWeakBox<id<iTermLineBlockObserver>> *box) {
        return [box.object isEqual:observer];
    }];
}

static void *iTermMemdup(const void *data, size_t count, size_t size) {
    void *dest = calloc(count, size);
    const size_t numBytes = count * size;
    memcpy(dest, data, numBytes);
    return dest;
}

- (id)modifyWithBlock:(id (^)(id<iTermLineBlockMutationCertificate>))block {
    // Synchronize for the duration of the mutation because -cowCopy will invalidate and nil out the certificate.
    @synchronized([LineBlock class]) {
        return block([self validMutationCertificate]);
    }
}

// On exit, these postconditions are guaranteed:
// self.owner==nil
// self.clients.arrayByStrongifyingWeakBoxes.count==0.
- (id<iTermLineBlockMutationCertificate>)validMutationCertificate {
    @synchronized([LineBlock class]) {
        if (!_cachedMutationCert) {
            _cachedMutationCert = [[iTermLineBlockMutator alloc] initWithLineBlock:self];
        }
        assert(self.clients != nil);

        NSArray<LineBlock *> *myClients = self.clients.arrayByStrongifyingWeakBoxes;
        if (self.owner == nil && !myClients.count) {
            // I have neither an owner nor clients, so copy-on-write is unneeded.
            return (id<iTermLineBlockMutationCertificate>)_cachedMutationCert;
        }

        // Perform copy-on-write copying.
        const ptrdiff_t offset = buffer_start - raw_buffer;
        iTermAssignToConstPointer((void **)&raw_buffer, iTermMemdup(self->raw_buffer, buffer_size, sizeof(screen_char_t)));
        buffer_start = raw_buffer + offset;
        iTermAssignToConstPointer((void **)&cumulative_line_lengths, iTermMemdup(self->cumulative_line_lengths, cll_capacity, sizeof(int)));

        if (self.owner != nil) {
            // I am no longer a client. Remove myself from my owner's client list.
            [self.owner.clients removeObjectsPassingTest:^BOOL(iTermWeakBox<LineBlock *> *box) {
                return box.object == self;
            }];
            // Since I am not a client anymore, I now have no owner.
            self.owner = nil;
        }

        if (myClients.count == 0) {
            // I have no clients.
            // Nothing else to do since my owner pointer was already nilled out.
            [self.clients removeAllObjects];
            return (id<iTermLineBlockMutationCertificate>)_cachedMutationCert;
        }

        // I have one or more clients.
        assert(myClients.count >= 1);

        // Designate the first client as the owner.
        LineBlock *newOwner = myClients[0];

        // The new owner should not have an owner anymore.
        assert(newOwner.owner == self);
        newOwner.owner = nil;

        // Transfer ownership of additional clients to newOwner.
        for (LineBlock *client in [myClients subarrayFromIndex:1]) {
            assert(client != newOwner);
            client.owner = newOwner;
            [newOwner.clients addObject:[iTermWeakBox boxFor:client]];
        }

        // All clients were transferred and now I should have none.
        [self.clients removeAllObjects];
        return (id<iTermLineBlockMutationCertificate>)_cachedMutationCert;
    }
}

- (LineBlock *)cowCopy {
    @synchronized([LineBlock class]) {
        // Make a shallow copy, sharing memory with me (and I may even be a shallow copy of some other LineBlock).
        LineBlock *copy = [self copyDeep:NO];

        // Walk owner pointers up to the root.
        LineBlock *owner = self;
        while (owner.owner) {
            owner = owner.owner;
        }

        // Create ownership relation.
        copy.owner = owner;
        [owner.clients addObject:[iTermWeakBox boxFor:copy]];

        [(id<iTermLineBlockMutationCertificate>)_cachedMutationCert invalidate];
        _cachedMutationCert = nil;
        copy->_progenitor = self;
        
        return copy;
    }
}

- (NSInteger)numberOfClients {
    @synchronized([LineBlock class]) {
        return self.clients.count;
    }
}

- (BOOL)hasOwner {
    @synchronized([LineBlock class]) {
        return self.owner != nil;
    }
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
    return (screen_char_t *)_lineBlock->raw_buffer;
}

- (void)setRawBufferCapacity:(size_t)count {
    assert(_valid);
    iTermAssignToConstPointer((void **)&_lineBlock->raw_buffer,
                              iTermRealloc((void*)_lineBlock->raw_buffer, count, sizeof(screen_char_t)));
}

- (void)setCumulativeLineLengthsCapacity:(int)capacity {
    assert(_valid);
    iTermAssignToConstPointer((void **)&_lineBlock->cumulative_line_lengths,
                              iTermRealloc((void *)_lineBlock->cumulative_line_lengths, capacity, sizeof(int)));
}

@end

