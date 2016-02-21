//
//  LineBlock.m
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import "LineBlock.h"
#import "FindContext.h"
#import "LineBufferHelpers.h"
#import "RegexKitLite.h"

NSString *const kLineBlockRawBufferKey = @"Raw Buffer";
NSString *const kLineBlockBufferStartOffsetKey = @"Buffer Start Offset";
NSString *const kLineBlockStartOffsetKey = @"Start Offset";
NSString *const kLineBlockFirstEntryKey = @"First Entry";
NSString *const kLineBlockBufferSizeKey = @"Buffer Size";
NSString *const kLineBlockCLLKey = @"Cumulative Line Lengths";
NSString *const kLineBlockIsPartialKey = @"Is Partial";
NSString *const kLineBlockMetadataKey = @"Metadata";
NSString *const kLineBlockMayHaveDWCKey = @"May Have Double Width Character";

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
    cached_numlines_width = -1;
    if (cll_capacity > 0) {
        metadata_ = (LineBlockMetadata *)malloc(sizeof(LineBlockMetadata) * cll_capacity);
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

        NSArray *metadataArray = dictionary[kLineBlockMetadataKey];
        metadata_ = (LineBlockMetadata *)calloc(cll_capacity, sizeof(LineBlockMetadata));

        for (int i = 0; i < cll_capacity; i++) {
            cumulative_line_lengths[i] = [cllArray[i] intValue];
            int j = 0;
            metadata_[i].continuation.code = [metadataArray[i][j++] unsignedShortValue];
            metadata_[i].continuation.backgroundColor = [metadataArray[i][j++] unsignedCharValue];
            metadata_[i].continuation.bgGreen = [metadataArray[i][j++] unsignedCharValue];
            metadata_[i].continuation.bgBlue = [metadataArray[i][j++] unsignedCharValue];
            metadata_[i].continuation.backgroundColorMode = [metadataArray[i][j++] unsignedCharValue];
            metadata_[i].timestamp = [metadataArray[i][j++] doubleValue];
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
    }
    cumulative_line_lengths[cll_entries] = cumulativeLength;
    metadata_[cll_entries].timestamp = timestamp;
    metadata_[cll_entries].continuation = continuation;
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

- (void)dump:(int)rawOffset
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
        NSLog(@"Line %d, length %d, offset from raw=%d, abs pos=%d, continued=%s: %s\n", i, cumulative_line_lengths[i] - prev, prev, prev + rawOffset, iscont?"yes":"no",
              formatsct(buffer_start+prev-start_offset, cumulative_line_lengths[i]-prev, temp));
        prev = cumulative_line_lengths[i];
    }
}

int NumberOfFullLines(screen_char_t* buffer, int length, int width,
                      BOOL mayHaveDoubleWidthCharacter)
{
    if (mayHaveDoubleWidthCharacter) {
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
      continuation:(screen_char_t)continuation
{
    const int space_used = [self rawSpaceUsed];
    const int free_space = buffer_size - space_used - start_offset;
    if (length > free_space) {
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
            int oldnum = NumberOfFullLines(buffer_start + prev_cll, old_length, width,
                                           _mayHaveDoubleWidthCharacter);
            int newnum = NumberOfFullLines(buffer_start + prev_cll, old_length + length, width,
                                           _mayHaveDoubleWidthCharacter);
            cached_numlines += newnum - oldnum;
        }

        cumulative_line_lengths[cll_entries - 1] += length;
        metadata_[cll_entries - 1].timestamp = timestamp;
        metadata_[cll_entries - 1].continuation = continuation;
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
            cached_numlines += NumberOfFullLines(buffer, length, width,
                                                 _mayHaveDoubleWidthCharacter) + 1;
        }
#ifdef TEST_LINEBUFFER_SANITY
        [self checkAndResetCachedNumlines:"appendLine normal case" width: width];
#endif
    }
    is_partial = partial;
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

int OffsetOfWrappedLine(screen_char_t* p, int n, int length, int width, BOOL mayHaveDwc) {
    if (mayHaveDwc) {
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
        int spans = NumberOfFullLines(buffer_start + prev,
                                      length,
                                      width,
                                      _mayHaveDoubleWidthCharacter);
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
    int prev = 0;
    int length;
    int i;
    int numEmptyLines = 0;
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        length = cll - prev;
        if (length == 0) {
            ++numEmptyLines;
        } else {
            numEmptyLines = 0;
        }
        int spans = NumberOfFullLines(buffer_start + prev,
                                      length,
                                      width,
                                      _mayHaveDoubleWidthCharacter);
        if (*lineNum > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            *lineNum -= consume;
        } else {  // *lineNum <= spans
            // We found the raw line that inclues the wrapped line we're searching for.
            // eat up *lineNum many width-sized wrapped lines from this start of the current full line
            int offset = OffsetOfWrappedLine(buffer_start + prev,
                                             *lineNum,
                                             length,
                                             width,
                                             _mayHaveDoubleWidthCharacter);
            *lineNum = 0;
            // offset: the relevant part of the raw line begins at this offset into it
            *lineLength = length - offset;  // the length of the suffix of the raw line, beginning at the wrapped line we want
            if (*lineLength > width) {
                // return an infix of the full line
                if (buffer_start[prev + offset + width].code == DWC_RIGHT) {
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

- (int) getNumLinesWithWrapWidth: (int) width
{
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
        count += NumberOfFullLines(buffer_start + prev,
                                   length,
                                   width,
                                   _mayHaveDoubleWidthCharacter) + 1;
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
           continuation:(screen_char_t *)continuationPtr
{
    if (cll_entries == first_entry) {
        // There is no last line to pop.
        return NO;
    }
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
        int offset_from_start = OffsetOfWrappedLine(buffer_start + start,
                                                    NumberOfFullLines(buffer_start + start,
                                                                      available_len,
                                                                      width,
                                                                      _mayHaveDoubleWidthCharacter),
                                                    available_len,
                                                    width,
                                                    _mayHaveDoubleWidthCharacter);
        *length = available_len - offset_from_start;
        *ptr = buffer_start + start + offset_from_start;
        cumulative_line_lengths[cll_entries - 1] -= *length;
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

- (void)changeBufferSize:(int)capacity
{
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

- (int)dropLines:(int)n withWidth:(int)width chars:(int *)charsDropped
{
    int orig_n = n;
    int prev = 0;
    int length;
    int i;
    *charsDropped = 0;
    int initialOffset = start_offset;
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        length = cll - prev;
        // Get the number of full-length wrapped lines in this raw line. If there
        // were only single-width characters the formula would be:
        //     (length - 1) / width;
        int spans = NumberOfFullLines(buffer_start + prev,
                                      length,
                                      width,
                                      _mayHaveDoubleWidthCharacter);
        if (n > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            n -= consume;
        } else {  // n <= spans
            // We found the raw line that inclues the wrapped line we're searching for.
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
            *charsDropped = start_offset - initialOffset;

#ifdef TEST_LINEBUFFER_SANITY
            [self checkAndResetCachedNumlines:"dropLines" width: width];
#endif
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
    //   - it is preceeded by an unescaped [
    //   - it is preceeded by an unescaped [:
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

static int CoreSearch(NSString* needle, screen_char_t* rawline, int raw_line_length, int start, int end,
                      FindOptions options, int* resultLength, NSString* haystack, unichar* charHaystack,
                      int* deltas, int deltaOffset) {
    int apiOptions = 0;
    NSRange range;
    BOOL regex;
    if (options & FindOptRegex) {
        regex = YES;
    } else {
        regex = NO;
    }
    if (regex) {
        BOOL backwards = NO;
        if (options & FindOptBackwards) {
            backwards = YES;
        }
        if (options & FindOptCaseInsensitive) {
            apiOptions |= RKLCaseless;
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
                --range.length;
                if (range.length == 0) {
                    // matched only on $
                    --range.location;
                }
            }
            if (hasPrefix && range.location == 0) {
                --range.length;
            } else if (hasPrefix) {
                --range.location;
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
        if (options & FindOptBackwards) {
            apiOptions |= NSBackwardsSearch;
        }
        if (options & FindOptCaseInsensitive) {
            apiOptions |= NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch;
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
    int result = CoreSearch(needle, rawline, raw_line_length, start, end, options, resultLength,
                            haystack, charHaystack, deltas, deltas[0]);

    free(deltas);
    free(charHaystack);
    return result;
}

- (void) _findInRawLine:(int) entry
                 needle:(NSString*)needle
                options:(int) options
                   skip:(int) skip
                 length:(int) raw_line_length
        multipleResults:(BOOL)multipleResults
                results:(NSMutableArray*)results
{
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
        // Example: Consider a previosu search of [jump]
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
        do {
            haystack = CharArrayToString(charHaystack, numUnichars);
            if ([haystack length] >= kMaxSaneStringLength) {
                // There's a bug in OS 10.9.0 (and possibly other versions) where the string
                // @"a⃑" reports a length of 0x7fffffffffffffff, which causes this loop to never
                // terminate.
                break;
            }
            tempPosition = CoreSearch(needle, rawline, raw_line_length, 0, limit, options,
                                      &tempResultLength, haystack, charHaystack, deltas, 0);

            limit = tempPosition + tempResultLength - 1;
            // find i so that i-deltas[i] == limit
            while (numUnichars >= 0 && numUnichars + deltas[numUnichars] > limit) {
                --numUnichars;
            }
            if (tempPosition != -1 && tempPosition <= skip) {
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
                                  options, &tempResultLength);
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
             atOffset:(int)offset
              results:(NSMutableArray*)results
      multipleResults:(BOOL)multipleResults
{
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
        [self _findInRawLine:entry
                      needle:substring
                     options:options
                        skip:skipped
                      length:[self _lineLength: entry]
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
                    toY:(int*)y
{
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
            int spans = NumberOfFullLines(raw_buffer + prev,
                                          line_length,
                                          width,
                                          _mayHaveDoubleWidthCharacter);
            *y += spans + 1;
        } else {
            // The position we're searching for is in this (unwrapped) line.
            int bytes_to_consume_in_this_line = position - prev;
            int dwc_peek = 0;

            // If the position is the left half of a double width char then include the right half in
            // the following call to NumberOfFullLines.

            if (bytes_to_consume_in_this_line < line_length &&
                prev + bytes_to_consume_in_this_line + 1 < eol) {
                assert(prev + bytes_to_consume_in_this_line + 1 < buffer_size);
                if (raw_buffer[prev + bytes_to_consume_in_this_line + 1].code == DWC_RIGHT) {
                    ++dwc_peek;
                }
            }
            int consume = NumberOfFullLines(raw_buffer + prev,
                                            MIN(line_length, bytes_to_consume_in_this_line + 1 + dwc_peek),
                                            width,
                                            _mayHaveDoubleWidthCharacter);
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
    NSData *rawBufferData = [NSData dataWithBytesNoCopy:raw_buffer
                                                        length:[self rawSpaceUsed] * sizeof(screen_char_t)
                                                  freeWhenDone:NO];
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

@end
