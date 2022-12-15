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
    BOOL _dirty;
    NSData *_cachedEncodedMetadata;
}

- (instancetype)initWithWidth:(int)width {
    self = [super init];
    if (self) {
        width_ = width;
        _dirty = NO;
        [self setDirty:NO inRange:VT100GridRangeMake(0, width) updateTimestampTo:0];
        iTermMetadataInit(&_metadata, 0, nil);
    }
    return self;
}

- (void)dealloc {
    iTermMetadataRelease(_metadata);
}

- (void)setDirty:(BOOL)dirty inRange:(VT100GridRange)range updateTimestampTo:(NSTimeInterval)now {
#ifdef ITERM_DEBUG
    assert(range.location >= 0);
    assert(range.length >= 0);
    assert(range.location + range.length <= width_);
#endif
    if (dirty && now) {
        [self updateTimestamp:now];
    }
    _dirty = dirty;
}

- (iTermImmutableMetadata)immutableMetadata {
    return iTermMetadataMakeImmutable(self.metadata);
}

- (VT100GridRange)dirtyRange {
    if (_dirty) {
        return VT100GridRangeMake(0, width_);
    } else {
        return VT100GridRangeMake(-1, -1);
    }
}

- (void)updateTimestamp:(NSTimeInterval)now __attribute__((objc_direct)) {
#ifdef ITERM_DEBUG
    assert(now > 0);
#endif
    _metadata.timestamp = round(now);
    _cachedEncodedMetadata = nil;
}

- (BOOL)isDirtyAtOffset:(int)x {
#if ITERM_DEBUG
    assert(x >= 0 && x < width_);
#endif
    return _dirty;
}

- (NSIndexSet *)dirtyIndexes {
    if (_dirty) {
        return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, width_)];
    }
    return [NSIndexSet indexSet];
}

- (BOOL)anyCharIsDirty {
    return _dirty;
}

- (id)copyWithZone:(NSZone *)zone {
    VT100LineInfo *theCopy = [[VT100LineInfo alloc] initWithWidth:width_];
    theCopy->_dirty = _dirty;
    iTermMetadataRelease(theCopy->_metadata);
    theCopy->_metadata = iTermMetadataCopy(_metadata);

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

- (void)setMetadataFromImmutable:(iTermImmutableMetadata)metadata {
    iTermMetadata mutableCopy = iTermImmutableMetadataMutableCopy(metadata);
    [self setMetadata:mutableCopy];
    iTermMetadataRelease(mutableCopy);
}

- (iTermExternalAttributeIndex *)externalAttributesCreatingIfNeeded:(BOOL)create {
    _cachedEncodedMetadata = nil;
    return create ? iTermMetadataGetExternalAttributesIndexCreatingIfNeeded(&_metadata) : iTermMetadataGetExternalAttributesIndex(_metadata);
}

- (void)setExternalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex {
    iTermMetadataSetExternalAttributes(&_metadata, eaIndex);
}

#pragma mark - DVREncodable

- (NSData *)dvrEncodableData {
    if (!_cachedEncodedMetadata) {
        _cachedEncodedMetadata = iTermMetadataEncodeToData(_metadata);
    }
    return _cachedEncodedMetadata;
}

@end
