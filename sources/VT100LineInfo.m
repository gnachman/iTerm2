//
//  VT100LineInfo.m
//  iTerm
//
//  Created by George Nachman on 11/17/13.
//
//

#import "VT100LineInfo.h"

@implementation VT100LineInfo {
    int width_;
    NSTimeInterval timestamp_;
    int start_;
    int bound_;
    NSData *_cachedEncodedMetadata;
}

static NSInteger VT100LineInfoNextGeneration = 1;

- (instancetype)initWithWidth:(int)width {
    self = [super init];
    if (self) {
        width_ = width;
        start_ = -1;
        bound_ = -1;
        [self setDirty:NO inRange:VT100GridRangeMake(0, width) updateTimestamp:NO];
        iTermMetadataInit(&_metadata, 0, nil);
    }
    return self;
}

- (void)dealloc {
    iTermMetadataRelease(_metadata);
}

- (void)setDirty:(BOOL)dirty inRange:(VT100GridRange)range updateTimestamp:(BOOL)updateTimestamp {
#ifdef ITERM_DEBUG
    assert(range.location >= 0);
    assert(range.length >= 0);
    assert(range.location + range.length <= width_);
#endif
    const VT100GridRange before = [self dirtyRange];
    if (dirty && updateTimestamp) {
        [self updateTimestamp];
    }
    if (dirty) {
        if (start_ < 0) {
            start_ = range.location;
            bound_ = range.location + range.length;
        } else {
            start_ = MIN(start_, range.location);
            bound_ = MAX(bound_, range.location + range.length);
        }
    } else if (start_ >= 0) {
        // Unset part of the dirty region.
        int clearBound = range.location + range.length;
        if (range.location <= start_) {
            if (clearBound >= bound_) {
                start_ = bound_ = -1;
            } else if (clearBound > start_) {
                start_ = clearBound;
            }
        } else if (range.location < bound_ && clearBound >= bound_) {
            // Clear the right-hand part of the dirty region
            bound_ = range.location;
        }
    }
    const VT100GridRange after = [self dirtyRange];
    if (dirty && !VT100GridRangeEqualsRange(before, after)) {
        _generation = VT100LineInfoNextGeneration++;
    }
}

- (VT100GridRange)dirtyRange {
    return VT100GridRangeMake(start_, bound_ - start_);
}

- (void)updateTimestamp {
    _metadata.timestamp = [NSDate timeIntervalSinceReferenceDate];
    _cachedEncodedMetadata = nil;
}

- (BOOL)isDirtyAtOffset:(int)x {
#if ITERM_DEBUG
    assert(x >= 0 && x < width_);
#else
    x = MIN(width_ - 1, MAX(0, x));
#endif
    return x >= start_ && x < bound_;
}

- (NSIndexSet *)dirtyIndexes {
    return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(start_, bound_ - start_)];
}

- (BOOL)anyCharIsDirty {
    return start_ >= 0;
}

- (id)copyWithZone:(NSZone *)zone {
    VT100LineInfo *theCopy = [[VT100LineInfo alloc] initWithWidth:width_];
    theCopy->start_ = start_;
    theCopy->bound_ = bound_;
    theCopy->timestamp_ = timestamp_;

    return theCopy;
}

- (void)setTimestamp:(NSTimeInterval)timestamp {
    _metadata.timestamp = timestamp;
    _cachedEncodedMetadata = nil;
}

- (void)decodeMetadataArray:(NSArray *)array {
    iTermMetadataRelease(_metadata);
    iTermMetadataInitFromArray(&_metadata, array);
}

- (void)resetMetadata {
    iTermMetadataReset(&_metadata);
    _cachedEncodedMetadata = nil;
}

- (NSArray *)encodedMetadata {
    return iTermMetadataEncodeToArray(_metadata);
}

- (void)setMetadata:(iTermMetadata)metadata {
    iTermMetadataRetain(metadata);
    iTermMetadataRelease(_metadata);
    _metadata = metadata;
    _cachedEncodedMetadata = nil;
}

- (iTermExternalAttributeIndex *)externalAttributesCreatingIfNeeded:(BOOL)create {
    _cachedEncodedMetadata = nil;
    return create ? iTermMetadataGetExternalAttributesIndexCreatingIfNeeded(&_metadata) : iTermMetadataGetExternalAttributesIndex(_metadata);
}

#pragma mark - DVREncodable

- (NSData *)dvrEncodableData {
    if (!_cachedEncodedMetadata) {
        _cachedEncodedMetadata = iTermMetadataEncodeToData(_metadata);
    }
    return _cachedEncodedMetadata;
}

@end
