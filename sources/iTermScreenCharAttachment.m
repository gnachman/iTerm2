//
//  iTermScreenCharAttachment.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/31/20.
//

#import "iTermScreenCharAttachment.h"
#import "DebugLogging.h"
#import "iTermMalloc.h"
#import "NSObject+iTerm.h"

static NSString *iTermStringForScreenCharAttachment(const iTermScreenCharAttachment *att) {
    if (!att) {
        return @"(null)";
    }
    return [NSString stringWithFormat:@"ulc=(%d,%d,%d) ulcMode=%d",
            att->underlineRed, att->underlineGreen, att->underlineBlue, att->underlineColorMode];
}

static NSString *iTermStringForScreenCharAttachmentRun(const iTermScreenCharAttachmentRun *run) {
    return [NSString stringWithFormat:@"[%d,%d]={%@}", run->offset, run->offset + run->length - 1,
            iTermStringForScreenCharAttachment(&run->attachment)];
}

static BOOL iTermScreenCharAttachmentsArrayEqual(id<iTermScreenCharAttachmentsArray> lhs,
                                                 id<iTermScreenCharAttachmentsArray> object) {
    if (![object conformsToProtocol:@protocol(iTermScreenCharAttachmentsArray)]) {
        return NO;
    }
    id<iTermScreenCharAttachmentsArray> rhs = (id<iTermScreenCharAttachmentsArray>)object;
    if (![rhs.validAttachments isEqual:lhs.validAttachments]) {
        return NO;
    }
    __block BOOL result = YES;
    const iTermScreenCharAttachment *myAttachments = lhs.attachments;
    const iTermScreenCharAttachment *otherAttachments = rhs.attachments;
    [lhs.validAttachments enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
        if (memcmp(&myAttachments[i],
                   &otherAttachments[i],
                   sizeof(*myAttachments))) {
            result = NO;
            *stop = YES;
        }
    }];
    return result;
}

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

- (NSString *)description {
    NSMutableArray *values = [NSMutableArray array];
    for (int i = 0; i < _count; i++) {
        [values addObject:iTermStringForScreenCharAttachmentRun(&_runs[i])];
    }
    NSString *summary = [values componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"<%@: %p count=%@ %@>",
            NSStringFromClass(self.class), self, @(_count), summary];
}

- (NSData *)serialized {
    return [NSData dataWithBytes:_runs length:_count * sizeof(*_runs)];
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
    assert(other != self);
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
            const int leftLength = location - offset;
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
        _range = range;
        _begin = [runArray sliceAt:range.location];
        if (_begin < 0) {
            _begin = runArray.count;
        }
        _end = [runArray sliceAt:NSMaxRange(range)];
        if (_end < 0) {
            _end = runArray.count;
        }
        _otherBaseOffset = runArray.baseOffset;
        _realArray = runArray;
    }
    return self;
}

- (NSString *)description {
    NSMutableArray *values = [NSMutableArray array];
    for (int i = 0; i < self.count; i++) {
        [values addObject:iTermStringForScreenCharAttachmentRun(&self.runs[i])];
    }
    NSString *summary = [values componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"<%@: %p count=%@ %@>",
            NSStringFromClass(self.class), self, @(self.count), summary];
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

static id<iTermScreenCharAttachmentRunArray>
iTermScreenCharAttachmentRunCreate(NSIndexSet *_validAttachments,
                                   const iTermScreenCharAttachment *_attachments,
                                   NSUInteger _count) {
    if (!_count) {
        return nil;
    }
    iTermScreenCharAttachmentRun *runs = iTermMalloc(sizeof(iTermScreenCharAttachmentRun) * _count);
    runs = iTermMalloc(_count * sizeof(*runs));
    __block int count = 0;
    __block int i = -1;
    __block int lastIndex = -1;
    const iTermScreenCharAttachment *attachments = _attachments;
    [_validAttachments enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        const iTermScreenCharAttachment *attachment = &attachments[idx];
        if (lastIndex == -1 ||  // Always start a run for the first index
            lastIndex + 1 != idx ||  // Start a run if there was a cap
            memcmp(attachment, &attachments[lastIndex], sizeof(*attachment))) {  // Start a run if the attachment is different than the last
            i = count;
            count += 1;
            runs[i].offset = idx;
            runs[i].length = 1;
            memmove(&runs[i].attachment, &_attachments[idx], sizeof(*_attachments));
        } else {
            runs[i].length += 1;
        }
        lastIndex = idx;
    }];
    return [iTermScreenCharAttachmentRunArray runArrayWithRuns:runs count:count];
}

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

- (instancetype)initWithRepeatedAttachment:(const iTermScreenCharAttachment *)attachment
                                     count:(NSUInteger)count {
    if (!attachment) {
        return nil;
    }
    self = [super init];
    if (self) {
        _validAttachments = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, count)];
        iTermScreenCharAttachment *mutableArray = iTermMalloc(count * sizeof(*attachment));
        _attachments = mutableArray;
        for (NSUInteger i = 0; i < count; i++) {
            mutableArray[i] = *attachment;
        }
        _count = count;
    }
    return self;
}

- (void)dealloc {
    free((void *)_attachments);
}

- (NSString *)description {
    NSMutableArray *values = [NSMutableArray array];
    [_validAttachments enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
        NSString *d = iTermStringForScreenCharAttachment(&self->_attachments[i]);
        [values addObject:[NSString stringWithFormat:@"%@={%@}", @(i), d]];
    }];
    NSString *summary = [values componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"<%@: %p %@>",
            NSStringFromClass(self.class), self, summary];
}

- (id<iTermScreenCharAttachmentRunArray>)runArray {
    return iTermScreenCharAttachmentRunCreate(_validAttachments, _attachments, _count);
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)object {
    return iTermScreenCharAttachmentsArrayEqual(self, object);
}

@end

@implementation iTermMutableScreenCharAttachmentsArray {
    iTermScreenCharAttachment *_mutableAttachments;  // has _count elements
    NSMutableIndexSet *_mutableValidAttachments;
}

@synthesize count = _count;

static iTermScreenCharAttachment gMagicAttachment;

- (instancetype)initWithCount:(NSUInteger)count {
    self = [super init];
    if (self) {
        _mutableAttachments = iTermCalloc(count + 1, sizeof(iTermScreenCharAttachment));
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            memset(&gMagicAttachment, 0xcd, sizeof(gMagicAttachment));
        });
        _mutableAttachments[count] = gMagicAttachment;
        _count = count;
        _mutableValidAttachments = [NSMutableIndexSet indexSet];
    }
    return self;
}

- (void)dealloc {
    assert(!memcmp(&gMagicAttachment, &_mutableAttachments[_count], sizeof(gMagicAttachment)));
    free(_mutableAttachments);
}

- (NSString *)description {
    NSMutableArray *values = [NSMutableArray array];
    [_mutableValidAttachments enumerateIndexesUsingBlock:^(NSUInteger i, BOOL * _Nonnull stop) {
        NSString *d = iTermStringForScreenCharAttachment(&self->_mutableAttachments[i]);
        [values addObject:[NSString stringWithFormat:@"%@={%@}", @(i), d]];
    }];
    NSString *summary = [values componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"<%@: %p %@>",
            NSStringFromClass(self.class), self, summary];
}

- (BOOL)isEqual:(id)object {
    return iTermScreenCharAttachmentsArrayEqual(self, object);
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

- (id<iTermScreenCharAttachmentRunArray>)runArray {
    return iTermScreenCharAttachmentRunCreate(_mutableValidAttachments, _mutableAttachments, _count);
}

- (void)copyAttachmentsInRange:(NSRange)rangeToCopy
                          from:(id<iTermScreenCharAttachmentsArray>)other {
    assert(self.count == other.count);
    [_mutableValidAttachments removeIndexesInRange:rangeToCopy];
    [other.validAttachments enumerateRangesInRange:rangeToCopy
                                           options:0
                                        usingBlock:^(NSRange range, BOOL * _Nonnull stop) {
        [self->_mutableValidAttachments addIndexesInRange:range];
        memmove(self.mutableAttachments + range.location,
                other.attachments + range.location,
                sizeof(iTermScreenCharAttachment) * range.length);
    }];
}

- (void)copyAttachmentsStartingAtIndex:(int)sourceIndex
                                    to:(int)destIndex
                                 count:(int)count {
    if (count == 0) {
        return;
    }
    if (sourceIndex == destIndex) {
        return;
    }
    NSMutableIndexSet *additions = [NSMutableIndexSet indexSet];
    const NSInteger offset = destIndex - sourceIndex;
    const NSEnumerationOptions opts = sourceIndex < destIndex ? NSEnumerationReverse : 0;
    [_mutableValidAttachments enumerateRangesInRange:NSMakeRange(sourceIndex, count)
                                             options:opts
                                          usingBlock:^(NSRange range, BOOL * _Nonnull stop) {
        memmove(&self->_mutableAttachments[range.location + offset],
                &self->_mutableAttachments[range.location],
                sizeof(iTermScreenCharAttachment) * range.length);
        [additions addIndexesInRange:NSMakeRange(range.location + offset, range.length)];
    }];
    [_mutableValidAttachments removeIndexesInRange:NSMakeRange(destIndex, count)];
    [_mutableValidAttachments addIndexes:additions];
}

- (void)removeAttachmentsInRange:(NSRange)range {
    [_mutableValidAttachments removeIndexesInRange:range];
}

- (void)setAttachment:(iTermScreenCharAttachment *)attachment
              inRange:(NSRange)range {
    if (!attachment) {
        [_mutableValidAttachments removeIndexesInRange:range];
        return;
    }
    [_mutableValidAttachments addIndexesInRange:range];
    for (NSInteger i = 0; i < range.length; i++) {
        _mutableAttachments[range.location + i] = *attachment;
    }
}

- (void)copyAttachmentsFromArray:(id<iTermScreenCharAttachmentsArray>)sourceArray
                      fromOffset:(int)sourceOffset
                        toOffset:(int)destOffset
                           count:(int)count {
    if (!sourceArray) {
        [_mutableValidAttachments removeIndexesInRange:NSMakeRange(destOffset, count)];
        return;
    }
    assert(count >= 0);
    assert(sourceOffset >= 0);
    assert(sourceOffset + count <= sourceArray.count);
    assert(destOffset >= 0);
    assert(destOffset + count <= _count);

    [_mutableValidAttachments addIndexesInRange:NSMakeRange(destOffset, count)];
    memmove(_mutableAttachments + destOffset,
            sourceArray.attachments + sourceOffset,
            count * sizeof(*_mutableAttachments));
}

@end
