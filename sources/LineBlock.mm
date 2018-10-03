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
#import "LineBufferHelpers.h"
#import "NSBundle+iTerm.h"
#import "RegexKitLite.h"
#import "iTermAdvancedSettingsModel.h"
}
#include <map>
#include <vector>

static BOOL gEnableDoubleWidthCharacterLineCache = NO;
static BOOL gUseCachingNumberOfLines = NO;

NSString *const kLineBlockRawBufferKey = @"Raw Buffer";
NSString *const kLineBlockBufferStartOffsetKey = @"Buffer Start Offset";
NSString *const kLineBlockStartOffsetKey = @"Start Offset";
NSString *const kLineBlockFirstEntryKey = @"First Entry";
NSString *const kLineBlockBufferSizeKey = @"Buffer Size";
NSString *const kLineBlockCLLKey = @"Cumulative Line Lengths";
NSString *const kLineBlockIsPartialKey = @"Is Partial";
NSString *const kLineBlockMetadataKey = @"Metadata";
NSString *const kLineBlockMayHaveDWCKey = @"May Have Double Width Character";

void EnableDoubleWidthCharacterLineCache() {
    gEnableDoubleWidthCharacterLineCache = YES;
}

@implementation LineBlock {
    // The raw lines, end-to-end. There is no delimiter between each line.
    screen_char_t* raw_buffer;
    screen_char_t* buffer_start;  // usable start of buffer (stuff before this is dropped)

    int start_offset;  // distance from raw_buffer to buffer_start
    int first_entry;  // first valid cumulative_line_length

    // The number of elements allocated for raw_buffer.
    int buffer_size;

    // There will be as many entries in this array as there are lines in raw_buffer.
    // The ith value is the length of the ith line plus the value of
    // cumulative_line_lengths[i-1] for i>0 or 0 for i==0.
    int* cumulative_line_lengths;
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
    std::map<std::tuple<int, int, int>, int> _numberOfFullLinesCache;

    std::vector<void *> _observers;
}

NS_INLINE void iTermLineBlockDidChange(__unsafe_unretained LineBlock *lineBlock) {
    for (auto &observer : lineBlock->_observers) {
        __unsafe_unretained id<iTermLineBlockObserver> obj = static_cast<id<iTermLineBlockObserver> >(observer);
        [obj lineBlockDidChange:lineBlock];
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (LineBlock*)initWithRawBufferSize:(int)size
{
    self = [super init];
    if (self) {
        raw_buffer = (screen_char_t*) malloc(sizeof(screen_char_t) * size);
        buffer_start = raw_buffer;
        buffer_size = size;
        // Allocate enough space for a bunch of 80-character lines. It can grow if needed.
        cll_capacity = 1 + size/80;
        cumulative_line_lengths = (int*) malloc(sizeof(int) * cll_capacity);
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

    cached_numlines_width = -1;
    if (cll_capacity > 0) {
        metadata_ = (LineBlockMetadata *)calloc(sizeof(LineBlockMetadata), cll_capacity);
    }
}

+ (instancetype)blockWithDictionary:(NSDictionary *)dictionary {
    return [[[self alloc] initWithDictionary:dictionary] autorelease];
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        NSArray *requiredKeys = @[ kLineBlockRawBufferKey,
                                   kLineBlockBufferStartOffsetKey,
                                   kLineBlockStartOffsetKey,
                                   kLineBlockFirstEntryKey,
                                   kLineBlockBufferSizeKey,
                                   kLineBlockCLLKey,
                                   kLineBlockMetadataKey,
                                   kLineBlockIsPartialKey,
                                   kLineBlockMayHaveDWCKey ];
        for (NSString *requiredKey in requiredKeys) {
            if (!dictionary[requiredKey]) {
                [self autorelease];
                return nil;
            }
        }
        NSData *data = dictionary[kLineBlockRawBufferKey];
        buffer_size = [dictionary[kLineBlockBufferSizeKey] intValue];
        raw_buffer = (screen_char_t *)malloc(buffer_size * sizeof(screen_char_t));
        memmove(raw_buffer, data.bytes, data.length);
        buffer_start = raw_buffer + [dictionary[kLineBlockBufferStartOffsetKey] intValue];
        start_offset = [dictionary[kLineBlockStartOffsetKey] intValue];
        first_entry = [dictionary[kLineBlockFirstEntryKey] intValue];

        NSArray *cllArray = dictionary[kLineBlockCLLKey];
        cll_capacity = [cllArray count];
        cumulative_line_lengths = (int*) malloc(sizeof(int) * cll_capacity);
        [self commonInit];

        NSArray *metadataArray = dictionary[kLineBlockMetadataKey];

        for (int i = 0; i < cll_capacity; i++) {
            cumulative_line_lengths[i] = [cllArray[i] intValue];
            int j = 0;
            NSArray *components = metadataArray[i];
            metadata_[i].continuation.code = [components[j++] unsignedShortValue];
            metadata_[i].continuation.backgroundColor = [components[j++] unsignedCharValue];
            metadata_[i].continuation.bgGreen = [components[j++] unsignedCharValue];
            metadata_[i].continuation.bgBlue = [components[j++] unsignedCharValue];
            metadata_[i].continuation.backgroundColorMode = [components[j++] unsignedCharValue];
            metadata_[i].timestamp = [components[j++] doubleValue];
            metadata_[i].number_of_wrapped_lines = 0;
            if (gEnableDoubleWidthCharacterLineCache) {
                metadata_[i].double_width_characters = nil;
            }
        }

        cll_entries = cll_capacity;
        is_partial = [dictionary[kLineBlockIsPartialKey] boolValue];
        _mayHaveDoubleWidthCharacter = [dictionary[kLineBlockMayHaveDWCKey] boolValue];
    }
    return self;
}

- (void)dealloc
{
    if (raw_buffer) {
        free(raw_buffer);
    }
    if (cumulative_line_lengths) {
        free(cumulative_line_lengths);
    }
    if (metadata_) {
        if (gEnableDoubleWidthCharacterLineCache) {
            for (int i = 0; i < cll_capacity; i++) {
                [metadata_[i].double_width_characters release];
            }
        }
        free(metadata_);
    }
    [super dealloc];
}

- (LineBlock *)copyWithZone:(NSZone *)zone {
    LineBlock *theCopy = [[LineBlock alloc] init];
    theCopy->raw_buffer = (screen_char_t*) malloc(sizeof(screen_char_t) * buffer_size);
    memmove(theCopy->raw_buffer, raw_buffer, sizeof(screen_char_t) * buffer_size);
    size_t bufferStartOffset = (buffer_start - raw_buffer);
    theCopy->buffer_start = theCopy->raw_buffer + bufferStartOffset;
    theCopy->start_offset = start_offset;
    theCopy->first_entry = first_entry;
    theCopy->buffer_size = buffer_size;
    size_t cll_size = sizeof(int) * cll_capacity;
    theCopy->cumulative_line_lengths = (int*) malloc(cll_size);
    memmove(theCopy->cumulative_line_lengths, cumulative_line_lengths, cll_size);
    theCopy->metadata_ = (LineBlockMetadata *) malloc(sizeof(LineBlockMetadata) * cll_capacity);
    memmove(theCopy->metadata_, metadata_, sizeof(LineBlockMetadata) * cll_capacity);
    for (int i = 0; i < cll_capacity; i++) {
        theCopy->metadata_[i].width_for_number_of_wrapped_lines = 0;
        theCopy->metadata_[i].number_of_wrapped_lines = 0;
        if (gEnableDoubleWidthCharacterLineCache) {
            theCopy->metadata_[i].double_width_characters = nil;
        }
    }
    theCopy->cll_capacity = cll_capacity;
    theCopy->cll_entries = cll_entries;
    theCopy->is_partial = is_partial;
    theCopy->cached_numlines = cached_numlines;
    theCopy->cached_numlines_width = cached_numlines_width;

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
                          timestamp:(NSTimeInterval)timestamp
                       continuation:(screen_char_t)continuation
{
    if (cll_entries == cll_capacity) {
        cll_capacity *= 2;
        cll_capacity = MAX(1, cll_capacity);
        cumulative_line_lengths = (int*) realloc((void*) cumulative_line_lengths, cll_capacity * sizeof(int));
        metadata_ = (LineBlockMetadata *)realloc((void *)metadata_, cll_capacity * sizeof(LineBlockMetadata));
        if (gEnableDoubleWidthCharacterLineCache) {
            memset(metadata_ + cll_entries,
                   0,
                   sizeof(LineBlockMetadata) * (cll_capacity - cll_entries));
        }
    }
    cumulative_line_lengths[cll_entries] = cumulativeLength;
    metadata_[cll_entries].timestamp = timestamp;
    metadata_[cll_entries].continuation = continuation;
    metadata_[cll_entries].number_of_wrapped_lines = 0;

    ++cll_entries;
}

// used by dump to format a line of screen_char_t's into an asciiz string.
static char* formatsct(screen_char_t* src, int len, char* dest) {
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
        if (toDebugLog) {
            DLog(@"%@", message);
        } else {
            NSLog(@"%@", message);
        }
        prev = cumulative_line_lengths[i];
    }
}

- (int)numberOfFullLinesFromOffset:(int)offset
                            length:(int)length
                             width:(int)width {
    auto key = std::tuple<int, int, int>(offset, length, width);
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

- (int)numberOfFullLinesFromBuffer:(screen_char_t *)buffer
                            length:(int)length
                             width:(int)width {
    return [self numberOfFullLinesFromOffset:buffer - raw_buffer
                                      length:length
                                       width:width];
}

extern "C" int iTermLineBlockNumberOfFullLinesImpl(screen_char_t *buffer,
                                                   int length,
                                                   int width,
                                                   BOOL mayHaveDoubleWidthCharacter) {
    if (width > 1 && mayHaveDoubleWidthCharacter) {
        int fullLines = 0;
        for (int i = width; i < length; i += width) {
            if (buffer[i].code == DWC_RIGHT) {
                --i;
            }
            ++fullLines;
        }
        return fullLines;
    } else {
        return (length - 1) / width;
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

- (BOOL)appendLine:(screen_char_t*)buffer
            length:(int)length
           partial:(BOOL)partial
             width:(int)width
         timestamp:(NSTimeInterval)timestamp
      continuation:(screen_char_t)continuation {
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
    memcpy(raw_buffer + space_used, buffer, sizeof(screen_char_t) * length);
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
        NSAssert(cll_entries > 0, @"is_partial but has no entries");
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

        cumulative_line_lengths[cll_entries - 1] += length;
        metadata_[cll_entries - 1].timestamp = timestamp;
        metadata_[cll_entries - 1].continuation = continuation;
        metadata_[cll_entries - 1].number_of_wrapped_lines = 0;
        if (gEnableDoubleWidthCharacterLineCache) {
            // TODO: Would be nice to add on to the index set instead of deleting it.
            [metadata_[cll_entries - 1].double_width_characters release];
            metadata_[cll_entries - 1].double_width_characters = nil;
        }
#ifdef TEST_LINEBUFFER_SANITY
        [self checkAndResetCachedNumlines:@"appendLine partial case" width: width];
#endif
    } else {
        // add a new line
        [self _appendCumulativeLineLength:(space_used + length)
                                timestamp:timestamp
                             continuation:continuation];
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

- (int)getPositionOfLine:(int*)lineNum
                     atX:(int)x
               withWidth:(int)width
                 yOffset:(int *)yOffsetPtr
                 extends:(BOOL *)extendsPtr
{
    int length;
    int eol;
    screen_char_t* p = [self getWrappedLineWithWrapWidth:width
                                                 lineNum:lineNum
                                              lineLength:&length
                                       includesEndOfLine:&eol
                                                 yOffset:yOffsetPtr
                                            continuation:NULL];
    if (!p) {
        return -1;
    } else {
        if (x >= length) {
            *extendsPtr = YES;
            return p - raw_buffer + length;
        } else {
            *extendsPtr = NO;
            return p - raw_buffer + x;
        }
    }
}

- (void)populateDoubleWidthCharacterCacheInMetadata:(LineBlockMetadata *)metadata
                                             buffer:(screen_char_t *)p
                                             length:(int)length
                                              width:(int)width {
    assert(gEnableDoubleWidthCharacterLineCache);
    [metadata->double_width_characters release];
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
        if (p[i].code == DWC_RIGHT) {
            // Oops, the line starts with the second half of a double-width
            // character. Wrap the last character of the previous line on to
            // this line.
            i--;
            [metadata->double_width_characters addIndex:lines];
        }
    }
}

- (int)offsetOfWrappedLineInBuffer:(screen_char_t *)p
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
int OffsetOfWrappedLine(screen_char_t* p, int n, int length, int width, BOOL mayHaveDwc) {
    if (width > 1 && mayHaveDwc) {
        int lines = 0;
        int i = 0;
        while (lines < n) {
            // Advance i to the start of the next line
            i += width;
            ++lines;
            assert(i < length);
            if (p[i].code == DWC_RIGHT) {
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

- (NSTimeInterval)timestampForLineNumber:(int)lineNum width:(int)width
{
    int prev = 0;
    int length;
    int i;
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        length = cll - prev;
        const int spans = [self numberOfFullLinesFromOffset:(buffer_start - raw_buffer) + prev
                                                     length:length
                                                      width:width];
        if (lineNum > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            lineNum -= consume;
        } else {  // *lineNum <= spans
            return metadata_[i].timestamp;
        }
        prev = cll;
    }
    return 0;
}

- (screen_char_t*)getWrappedLineWithWrapWidth:(int)width
                                      lineNum:(int*)lineNum
                                   lineLength:(int*)lineLength
                            includesEndOfLine:(int*)includesEndOfLine
                                 continuation:(screen_char_t *)continuationPtr
{
    return [self getWrappedLineWithWrapWidth:width
                                     lineNum:lineNum
                                  lineLength:lineLength
                           includesEndOfLine:includesEndOfLine
                                     yOffset:NULL
                                continuation:continuationPtr];
}

- (screen_char_t*)getWrappedLineWithWrapWidth:(int)width
                                      lineNum:(int*)lineNum
                                   lineLength:(int*)lineLength
                            includesEndOfLine:(int*)includesEndOfLine
                                      yOffset:(int*)yOffsetPtr
                                 continuation:(screen_char_t *)continuationPtr
{
    ITBetaAssert(*lineNum >= 0, @"Negative lines to getWrappedLineWithWrapWidth");
    int prev = 0;
    int numEmptyLines = 0;
    for (int i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        const int length = cll - prev;
        if (length == 0) {
            ++numEmptyLines;
        } else {
            numEmptyLines = 0;
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
            int offset;
            if (gEnableDoubleWidthCharacterLineCache) {
                offset = [self offsetOfWrappedLineInBuffer:buffer_start + prev
                                         wrappedLineNumber:*lineNum
                                              bufferLength:length
                                                     width:width
                                                  metadata:&metadata_[i]];
            } else {
                offset = OffsetOfWrappedLine(buffer_start + prev,
                                             *lineNum,
                                             length,
                                             width,
                                             _mayHaveDoubleWidthCharacter);
            }

            *lineNum = 0;
            // offset: the relevant part of the raw line begins at this offset into it
            *lineLength = length - offset;  // the length of the suffix of the raw line, beginning at the wrapped line we want
            if (*lineLength > width) {
                // return an infix of the full line
                if (width > 1 && buffer_start[prev + offset + width].code == DWC_RIGHT) {
                    // Result would end with the first half of a double-width character
                    *lineLength = width - 1;
                    *includesEndOfLine = EOL_DWC;
                } else {
                    *lineLength = width;
                    *includesEndOfLine = EOL_SOFT;
                }
            } else {
                // return a suffix of the full line
                if (i == cll_entries - 1 && is_partial) {
                    // If this is the last line and it's partial then it doesn't have an end-of-line.
                    *includesEndOfLine = EOL_SOFT;
                } else {
                    *includesEndOfLine = EOL_HARD;
                }
            }
            if (yOffsetPtr) {
                // Set *yOffsetPtr to the number of consecutive empty lines just before the requested
                // line.
                *yOffsetPtr = numEmptyLines;
            }
            if (continuationPtr) {
                *continuationPtr = metadata_[i].continuation;
                continuationPtr->code = *includesEndOfLine;
            }
            return buffer_start + prev + offset;
        }
        prev = cll;
    }
    return NULL;
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

- (BOOL) hasCachedNumLinesForWidth: (int) width
{
    return cached_numlines_width == width;
}

- (BOOL)popLastLineInto:(screen_char_t**)ptr
             withLength:(int*)length
              upToWidth:(int)width
              timestamp:(NSTimeInterval *)timestampPtr
           continuation:(screen_char_t *)continuationPtr {
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
    if (timestampPtr) {
        *timestampPtr = metadata_[cll_entries - 1].timestamp;
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
        *ptr = buffer_start + start + offset_from_start;
        cumulative_line_lengths[cll_entries - 1] -= *length;
        metadata_[cll_entries - 1].number_of_wrapped_lines = 0;
        if (gEnableDoubleWidthCharacterLineCache) {
            [metadata_[cll_entries - 1].double_width_characters release];
            metadata_[cll_entries - 1].double_width_characters = nil;
        }

        is_partial = YES;
    } else {
        // The last raw line is not longer than width. Return the whole thing.
        *length = available_len;
        *ptr = buffer_start + start;
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

- (int)getRawLineLength:(int)linenum
{
    NSAssert(linenum < cll_entries && linenum >= 0, @"Out of bounds");
    int prev;
    if (linenum == 0) {
        prev = 0;
    } else {
        prev = cumulative_line_lengths[linenum-1] - start_offset;
    }
    return cumulative_line_lengths[linenum] - start_offset - prev;
}

- (screen_char_t*)rawLine:(int)linenum
{
    int start;
    if (linenum == 0) {
        start = 0;
    } else {
        start = cumulative_line_lengths[linenum - 1];
    }
    return raw_buffer + start;
}

- (void)changeBufferSize:(int)capacity {
    NSAssert(capacity >= [self rawSpaceUsed], @"Truncating used space");
    capacity = MAX(1, capacity);
    raw_buffer = (screen_char_t*) realloc((void*) raw_buffer, sizeof(screen_char_t) * capacity);
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

- (void)shrinkToFit
{
    [self changeBufferSize: [self rawSpaceUsed]];
}

- (int)dropLines:(int)n withWidth:(int)width chars:(int *)charsDropped {
    int orig_n = n;
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
                [metadata_[i].double_width_characters release];
                metadata_[i].double_width_characters = nil;
            }

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

- (int) _lineRawOffset: (int) anIndex
{
    if (anIndex == first_entry) {
        return start_offset;
    } else {
        return cumulative_line_lengths[anIndex - 1];
    }
}

const unichar kPrefixChar = 1;
const unichar kSuffixChar = 2;

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

static int CoreSearch(NSString *needle,
                      screen_char_t *rawline,
                      int raw_line_length,
                      int start,
                      int end,
                      FindOptions options,
                      iTermFindMode mode,
                      int *resultLength,
                      NSString *haystack,
                      unichar *charHaystack,
                      int *deltas,
                      int deltaOffset) {
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
        NSString* sanitizedHaystack = [haystack stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%c", kPrefixChar]
                                                                          withString:[NSString stringWithFormat:@"%c", 3]];
        sanitizedHaystack = [sanitizedHaystack stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%c", kSuffixChar]
                                                                         withString:[NSString stringWithFormat:@"%c", 3]];

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
            NSLog(@"regex error: %@", regexError);
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
        range = [haystack rangeOfString:needle options:apiOptions];
    }
    int result = -1;
    if (range.location != NSNotFound) {
        int adjustedLocation;
        int adjustedLength;
        adjustedLocation = range.location + deltas[range.location] + deltaOffset;
        adjustedLength = range.length + deltas[range.location + range.length] -
        (deltas[range.location] + deltaOffset);
        *resultLength = adjustedLength;
        result = adjustedLocation + start;
    }
    return result;
}

static int Search(NSString* needle,
                  screen_char_t* rawline,
                  int raw_line_length,
                  int start,
                  int end,
                  int options,
                  iTermFindMode mode,
                  int* resultLength)
{
    NSString* haystack;
    unichar* charHaystack;
    int* deltas;
    haystack = ScreenCharArrayToString(rawline,
                                       start,
                                       end,
                                       &charHaystack,
                                       &deltas);
    // screen_char_t[i + deltas[i]] begins its run at charHaystack[i]
    int result = CoreSearch(needle, rawline, raw_line_length, start, end, options, mode, resultLength,
                            haystack, charHaystack, deltas, deltas[0]);

    free(deltas);
    free(charHaystack);
    return result;
}

- (void)_findInRawLine:(int)entry
                needle:(NSString*)needle
               options:(int)options
                  mode:(iTermFindMode)mode
                  skip:(int)skip
                length:(int)raw_line_length
       multipleResults:(BOOL)multipleResults
               results:(NSMutableArray *)results {
    screen_char_t* rawline = raw_buffer + [self _lineRawOffset:entry];
    if (skip > raw_line_length) {
        skip = raw_line_length;
    }
    if (skip < 0) {
        skip = 0;
    }
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
        int tempResultLength;
        int tempPosition;

        NSString* haystack;
        unichar* charHaystack;
        int* deltas;
        haystack = ScreenCharArrayToString(rawline,
                                           0,
                                           limit,
                                           &charHaystack,
                                           &deltas);
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
            tempPosition = CoreSearch(needle, rawline, raw_line_length, 0, limit, options,
                                      mode, &tempResultLength, haystack, charHaystack, deltas, 0);

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
                ResultRange* r = [[[ResultRange alloc] init] autorelease];
                r->position = tempPosition;
                r->length = tempResultLength;
                [results addObject:r];
            }
        } while (tempPosition != -1 && (multipleResults || tempPosition > skip));
        free(deltas);
        free(charHaystack);
    } else {
        // Search forward
        // TODO: test this
        int tempResultLength;
        int tempPosition;
        while (skip < raw_line_length) {
            tempPosition = Search(needle, rawline, raw_line_length, skip, raw_line_length,
                                  options, mode, &tempResultLength);
            if (tempPosition != -1) {
                ResultRange* r = [[[ResultRange alloc] init] autorelease];
                r->position = tempPosition;
                r->length = tempResultLength;
                [results addObject:r];
                if (!multipleResults) {
                    break;
                }
                skip = tempPosition + 1;
            } else {
                break;
            }
        }
    }
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
              options:(int)options
                 mode:(iTermFindMode)mode
             atOffset:(int)offset
              results:(NSMutableArray *)results
      multipleResults:(BOOL)multipleResults {
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
        if ([newResults count] && !multipleResults) {
            return;
        }
        entry += dir;
    }
}

// Returns YES if the position is valid for this block.
- (BOOL)convertPosition:(int)position
              withWidth:(int)width
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
        if (position >= eol) {
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
                if (width > 1 && raw_buffer[prev + bytes_to_consume_in_this_line + 1].code == DWC_RIGHT) {
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
    NSLog(@"Didn't find position %d", position);
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
        [metadataArray addObject:@[ @(metadata_[i].continuation.code),
                                    @(metadata_[i].continuation.backgroundColor),
                                    @(metadata_[i].continuation.bgGreen),
                                    @(metadata_[i].continuation.bgBlue),
                                    @(metadata_[i].continuation.backgroundColorMode),
                                    @(metadata_[i].timestamp) ]];
    }
    return metadataArray;
}

- (NSDictionary *)dictionary {
    NSData *rawBufferData = [NSData dataWithBytes:raw_buffer
                                           length:[self rawSpaceUsed] * sizeof(screen_char_t)];
    return @{ kLineBlockRawBufferKey: rawBufferData,
              kLineBlockBufferStartOffsetKey: @(buffer_start - raw_buffer),
              kLineBlockStartOffsetKey: @(start_offset),
              kLineBlockFirstEntryKey: @(first_entry),
              kLineBlockBufferSizeKey: @(buffer_size),
              kLineBlockCLLKey: [self cumulativeLineLengthsArray],
              kLineBlockIsPartialKey: @(is_partial),
              kLineBlockMetadataKey: [self metadataArray],
              kLineBlockMayHaveDWCKey: @(_mayHaveDoubleWidthCharacter) };
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

- (void)addObserver:(id<iTermLineBlockObserver>)observer {
    _observers.push_back((void *)observer);
}

- (void)removeObserver:(id<iTermLineBlockObserver>)observer {
    void *voidptr = static_cast<void *>(observer);
    auto it = std::find(_observers.begin(), _observers.end(), voidptr);
    if (it != _observers.end()) {
        _observers.erase(it);
    }
}

- (BOOL)hasObserver:(id<iTermLineBlockObserver>)observer {
    void *voidptr = static_cast<void *>(observer);
    auto it = std::find(_observers.begin(), _observers.end(), voidptr);
    return it != _observers.end();
}

@end
