//
//  VT100ScreenCharAttachment.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/31/20.
//

#import "VT100ScreenCharAttachment.h"
#import "DebugLogging.h"
#import "iTermMalloc.h"

@implementation iTermScreenCharAttachmentRunArray {
    iTermScreenCharAttachmentRun *_runs;
    int _count;
}

@synthesize runs = _runs;

+ (instancetype)runArrayWithRuns:(iTermScreenCharAttachmentRun *)runs
                           count:(int)count {
    iTermScreenCharAttachmentRunArray *result = [[iTermScreenCharAttachmentRunArray alloc] init];
    result->_runs = runs;
    result->_count = count;
    return result;
}

- (instancetype)initWithSerialized:(NSData *)serialized {
    self = [super init];
    if (self) {
        if (serialized.length % sizeof(*_runs) || serialized.length >= INT_MAX) {
            ITBetaAssert(NO, @"Serialized length is %@", @(serialized.length));
            return nil;
        }
        _runs = iTermMalloc(sizeof(*_runs) * serialized.length);
        memmove(_runs, serialized.bytes, serialized.length);
        _count = serialized.length / sizeof(*_runs);
    }
    return self;
}

- (void)dealloc {
    free(_runs);
}

- (NSUInteger)count {
    return MAX(0, MIN(INT_MAX, _count));
}

- (id)copyWithZone:(NSZone *)zone {
    const size_t size = sizeof(*_runs) * _count;
    iTermScreenCharAttachmentRun *copyOfRuns = iTermMalloc(size);
    memmove(copyOfRuns, _runs, size);
    return [iTermScreenCharAttachmentRunArray runArrayWithRuns:copyOfRuns count:_count];
}

- (void)setBaseOffset:(int)baseOffset {
    const int delta = baseOffset - _baseOffset;
    for (int i = 0; i < _count; i++) {
        _runs[i].offset += delta;
    }
    _baseOffset = baseOffset;
}

- (void)append:(id<iTermScreenCharAttachmentRunArray>)other baseOffset:(int)baseOffset {
    if (!other) {
        return;
    }
    const NSInteger totalCount = _count + other.count;
    _runs = iTermRealloc(_runs, totalCount, sizeof(iTermScreenCharAttachmentRun));
    const int otherCount = other.count;
    const int offset = _count;
    const int adjustedBaseOffset = baseOffset - other.baseOffset;
    const iTermScreenCharAttachmentRun *otherRuns = other.runs;
    for (int i = 0; i < otherCount; i++) {
        _runs[i + offset].offset = adjustedBaseOffset + otherRuns[i].offset;
        _runs[i + offset].length = otherRuns[i].length;
        _runs[i + offset].attachment = otherRuns[i].attachment;
    }
    _count += otherCount;
}

// Find a run starting before location and ending after it. Break it in to two.
// Returns the index of the first run starting at or after `location` or -1.
// TODO: Use a binary search if this becomes a bottleneck
- (int)sliceAt:(int)location {
    for (int i = 0; i < _count; i++){
        const int offset = _runs[i].offset;
        const int length = _runs[i].length;
        if (offset + length < location) {
            continue;
        }
        if (offset >= location) {
            return i;
        }
        if (offset < location && offset + length > location) {
            _runs = iTermRealloc(_runs, _count + 1, sizeof(*_runs));
            memmove(&_runs[i + 1], &_runs[i], sizeof(*_runs) * (_count - i));
            _count++;
            const int leftLength = offset + length - location;
            const int rightLength = length - leftLength;
            _runs[i].length = leftLength;
            _runs[i+1].offset = location;
            _runs[i+1].length = rightLength;
            return i + 1;
        }
    }
    return -1;
}

// Gives the first index with a run.
- (int)begin {
    if (_count == 0) {
        return 0;
    }
    return _runs[0].offset;
}

// Gives the first index after the last run.
- (int)end {
    if (_count == 0) {
        return 0;
    }
    return _runs[_count - 1].offset + _runs[_count - 1].length;
}

// TODO: Cache these if it would be a win.
- (iTermScreenCharAttachmentRunArraySlice *)sliceFrom:(int)offset length:(int)sliceLength {
     return [[iTermScreenCharAttachmentRunArraySlice alloc] initWithRunArray:self
                                                                      range:NSMakeRange(offset, sliceLength)];
}

- (iTermScreenCharAttachmentRunArraySlice *)asSlice {
    return [self sliceFrom:0 length:self.end];
}

- (void)truncateFrom:(int)offset {
    if (offset == 0) {
        _count = 0;
        return;
    }
    const int i = [self sliceAt:offset];
    if (i != -1) {
        _count = i + 1;
    }
}

- (iTermScreenCharAttachmentRunArray *)makeRunArray {
    return self;
}

@end

@implementation iTermScreenCharAttachmentRunArraySlice {
    NSRange _range;
    int _otherBaseOffset;
    int _begin;
    int _end;
    iTermMutableScreenCharAttachmentsArray *_fullArray;
}

- (instancetype)initWithRunArray:(iTermScreenCharAttachmentRunArray *)runArray range:(NSRange)range {
    self = [super init];
    if (self) {
        _begin = [runArray sliceAt:range.location];
        _end = [runArray sliceAt:NSMaxRange(range)];
        _otherBaseOffset = runArray.baseOffset;
        _realArray = runArray;
    }
    return self;
}

- (NSUInteger)count {
    return _end - _begin;
}

- (int)baseOffset {
    return _otherBaseOffset + _range.location;
}

- (const iTermScreenCharAttachmentRun *)runs {
    return _realArray.runs + _begin;
}

- (iTermScreenCharAttachmentRunArray *)makeRunArray {
    return [iTermScreenCharAttachmentRunArray runArrayWithRuns:(iTermScreenCharAttachmentRun *)self.runs
                                                         count:self.count];
}

// Number of cells needed to store in its expanded form.
- (int)width {
    const NSUInteger count = self.count;
    if (count == 0) {
        return 0;
    }
    const iTermScreenCharAttachmentRun *lastRun = &_realArray.runs[count - 1];
    int result = lastRun->offset;
    result += lastRun->length;
    return result;
}

- (id<iTermScreenCharAttachmentsArray>)fullArray {
    if (_fullArray) {
        return _fullArray;
    }
    _fullArray = [[iTermMutableScreenCharAttachmentsArray alloc] initWithCount:self.width];
    iTermScreenCharAttachment *mutableAttachments = _fullArray.mutableAttachments;
    NSMutableIndexSet *validAttachments = _fullArray.mutableValidAttachments;

    const NSUInteger count = self.count;
    const iTermScreenCharAttachmentRun *runs = self.runs;
    for (NSUInteger i = 0; i < count; i++) {
        const iTermScreenCharAttachmentRun *run = &runs[i];
        for (int j = 0; j < run->length; j++) {
            [validAttachments addIndex:run->offset + j];
            mutableAttachments[run->offset + j] = run->attachment;
        }
    }
    return _fullArray;
}

@end

@implementation iTermScreenCharAttachmentsArray

@synthesize validAttachments = _validAttachments;
@synthesize attachments = _attachments;
@synthesize count = _count;

- (instancetype)initWithValidAttachmentIndexes:(NSIndexSet *)validAttachments
                                   attachments:(const iTermScreenCharAttachment *)attachments
                                         count:(NSUInteger)count {
    self = [super init];
    if (self) {
        _validAttachments = [validAttachments copy];
        _attachments = iTermMalloc(count * sizeof(*attachments));
        memmove((void *)_attachments, attachments, count * sizeof(*attachments));
        _count = count;
    }
    return self;
}

- (void)dealloc {
    free((void *)_attachments);
}

@end

@implementation iTermMutableScreenCharAttachmentsArray {
    iTermScreenCharAttachment *_mutableAttachments;  // has _count elements
    NSMutableIndexSet *_mutableValidAttachments;
}

@synthesize count = _count;

- (instancetype)initWithCount:(NSUInteger)count {
    self = [super init];
    if (self) {
        _mutableAttachments = iTermCalloc(count, sizeof(iTermScreenCharAttachment));
        _count = count;
        _mutableValidAttachments = [NSMutableIndexSet indexSet];
    }
    return self;
}

- (void)dealloc {
    free(_mutableAttachments);
}

- (const iTermScreenCharAttachment *)attachments {
    return _mutableAttachments;
}

- (iTermScreenCharAttachment *)mutableAttachments {
    return _mutableAttachments;
}

- (NSMutableIndexSet *)mutableValidAttachments {
    return _mutableValidAttachments;
}

- (NSIndexSet *)validAttachments {
    return _mutableValidAttachments;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[iTermScreenCharAttachmentsArray alloc] initWithValidAttachmentIndexes:_mutableValidAttachments
                                                                       attachments:_mutableAttachments
                                                                             count:_count];
}

- (instancetype)mutableCopy {
    iTermMutableScreenCharAttachmentsArray *copy = [[iTermMutableScreenCharAttachmentsArray alloc] initWithCount:_count];
    memmove((void *)copy->_mutableAttachments, _mutableAttachments, _count * sizeof(*_mutableAttachments));
    [copy->_mutableValidAttachments addIndexes:_mutableValidAttachments];
    return copy;
}

@end
