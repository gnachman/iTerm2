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
    const iTermScreenCharAttachmentRun *_runs;
    int _count;
}

@synthesize runs = _runs;

+ (instancetype)runArrayWithRuns:(const iTermScreenCharAttachmentRun *)runs
                           count:(int)count {
    assert(runs);
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
        iTermScreenCharAttachmentRun *runs = iTermMalloc(sizeof(*_runs) * serialized.length);
        memmove(runs, serialized.bytes, serialized.length);
        _runs = runs;
        _count = serialized.length / sizeof(*_runs);
    }
    return self;
}

- (void)dealloc {
    free((void *)_runs);
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

- (id<iTermScreenCharAttachmentsArray>)attachmentsArrayOfLength:(int)width {
    iTermMutableScreenCharAttachmentsArray *attachmentsArray =
    [[iTermMutableScreenCharAttachmentsArray alloc] initWithCount:width];
    iTermScreenCharAttachment *outArray = attachmentsArray.mutableAttachments;

    const iTermScreenCharAttachmentRun *runs = self.runs;
    const NSUInteger count = self.count;

    // Foreach run
    for (NSUInteger i = 0; i < count; i++) {
        const iTermScreenCharAttachmentRun *run = &runs[i];
        int offset = run->offset;
        assert(offset + run->length <= width);
        // Foreach cell affected by run
        for (int j = 0; j < run->length; j++) {
            outArray[offset + j] = run->attachment;
        }
        [attachmentsArray.mutableValidAttachments addIndexesInRange:NSMakeRange(offset, run->length)];
    }
    return attachmentsArray;
}

- (NSData *)serialized {
    return [NSData dataWithBytes:_runs length:_count * sizeof(*_runs)];
}

- (NSUInteger)count {
    return MAX(0, MIN(INT_MAX, _count));
}

- (id)copy {
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (id<iTermScreenCharAttachmentRunArray>)runsInRange:(NSRange)range
                                        addingOffset:(int)offset {
    if (self.count == 0) {
        return [self copy];
    }

    iTermScreenCharAttachmentsRunArrayBuilder *builder = [[iTermScreenCharAttachmentsRunArrayBuilder alloc] init];
    for (NSUInteger i = 0; i < self.count; i++) {
        const NSRange runRange = NSMakeRange(self.runs[i].offset, self.runs[i].length);
        const NSRange intersection = NSIntersectionRange(runRange, range);
        if (NSEqualRanges(runRange, intersection)) {
            [builder appendRuns:&self.runs[i] count:1 addingOffset:offset];
        } else if (intersection.length > 0 && intersection.location != NSNotFound) {
            iTermScreenCharAttachmentRun temp = self.runs[i];
            temp.offset = intersection.location;
            temp.length = intersection.length;
            [builder appendRuns:&temp count:1 addingOffset:offset];
        }
    }
    return builder.runArray;
}

- (id<iTermScreenCharAttachmentRunArray>)appending:(id<iTermScreenCharAttachmentRunArray>)suffix
                                      addingOffset:(int)offset {
    iTermScreenCharAttachmentsRunArrayBuilder *builder = [[iTermScreenCharAttachmentsRunArrayBuilder alloc] init];
    [builder appendRuns:self.runs count:self.count addingOffset:0];
    [builder appendRuns:suffix.runs count:suffix.count addingOffset:offset];
    return builder.runArray;
}

- (id<iTermScreenCharAttachmentRunArray>)runArrayByAddingOffset:(int)offset {
    iTermScreenCharAttachmentsRunArrayBuilder *builder = [[iTermScreenCharAttachmentsRunArrayBuilder alloc] init];
    [builder appendRuns:self.runs count:self.count addingOffset:offset];
    return builder.runArray;
}

@end

@implementation iTermScreenCharAttachmentsRunArrayBuilder {
    NSUInteger _count;
    NSUInteger _capacity;
    iTermScreenCharAttachmentRun *_runs;
}

- (void)dealloc {
    if (_runs) {
        free(_runs);
    }
}

- (void)appendRun:(const iTermScreenCharAttachmentRun *)run {
    [self appendRuns:run count:1 addingOffset:0];
}

- (id<iTermScreenCharAttachmentRunArray>)runArray {
    id<iTermScreenCharAttachmentRunArray> result =
        [iTermScreenCharAttachmentRunArray runArrayWithRuns:_runs count:_count];
    _runs = NULL;
    return result;
}

- (void)appendRuns:(const iTermScreenCharAttachmentRun *)runs
             count:(NSUInteger)count
      addingOffset:(int)offset {
    NSUInteger desiredCount = _count + count;
    if (!_runs) {
        _runs = iTermMalloc(sizeof(*runs) * desiredCount);
        _capacity = desiredCount;
    } else if (_count == _capacity) {
        while (_capacity < desiredCount) {
            _capacity *= 2;
        }
        _runs = iTermRealloc(_runs, _capacity, sizeof(*runs));
    }
    memmove(_runs + _count, runs, sizeof(*runs) * count);
    if (offset) {
        for (NSUInteger i = 0; i < count; i++) {
            _runs[_count + i].offset += offset;
        }
    }
    _count = desiredCount;
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
    id<iTermScreenCharAttachmentRunArray> _runArray;
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

- (void)markDirty {
    _dirty = YES;
    _runArray = nil;
}

- (iTermScreenCharAttachment *)mutableAttachments {
    [self markDirty];
    return _mutableAttachments;
}

- (NSMutableIndexSet *)mutableValidAttachments {
    [self markDirty];
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
    [self markDirty];
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
    [self markDirty];
}

- (void)removeAttachmentsInRange:(NSRange)range {
    [_mutableValidAttachments removeIndexesInRange:range];
    [self markDirty];
}

- (void)removeAllAttachments {
    [_mutableValidAttachments removeAllIndexes];
    [self markDirty];
}

- (void)setAttachment:(const iTermScreenCharAttachment *)attachment
              inRange:(NSRange)range {
    assert(NSMaxRange(range) <= _count);
    
    if (!attachment) {
        [_mutableValidAttachments removeIndexesInRange:range];
        return;
    }
    [_mutableValidAttachments addIndexesInRange:range];
    for (NSInteger i = 0; i < range.length; i++) {
        _mutableAttachments[range.location + i] = *attachment;
    }
    [self markDirty];
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
    [self markDirty];
}

- (void)setFromRuns:(id<iTermScreenCharAttachmentRunArray>)attachments {
    if (!attachments) {
        [_mutableValidAttachments removeAllIndexes];
        return;
    }
    for (NSInteger i = 0; i < attachments.count; i++) {
        [self setAttachment:&attachments.runs[i].attachment
                    inRange:NSMakeRange(attachments.runs[i].offset,
                                        attachments.runs[i].length)];
    }
    [self markDirty];
}

- (id<iTermScreenCharAttachmentRunArray>)runArray {
    if (_runArray) {
        return _runArray;
    }
    if (_mutableValidAttachments.count == 0) {
        return nil;
    }
    _runArray = iTermScreenCharAttachmentRunCreate(_mutableValidAttachments,
                                                   _mutableAttachments,
                                                   _count);
    return _runArray;
}

@end
