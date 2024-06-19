//
//  LineBlockMetadataArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/19/24.
//

#import "LineBlockMetadataArray.h"

#import "iTermMalloc.h"

@implementation LineBlockMetadataArray {
    LineBlockMetadata *_array;
    int _numEntries;  // Inclusive of _first.
}

- (instancetype)initWithCapacity:(int)capacity useDWCCache:(BOOL)useDWCCache {
    self = [super init];
    if (self) {
        _useDWCCache = useDWCCache;
        _array = (LineBlockMetadata *)iTermCalloc(sizeof(LineBlockMetadata), capacity);
        _capacity = capacity;
    }
    return self;
}

- (void)dealloc {
    if (!_array) {
        return;
    }
    if (_useDWCCache) {
        for (int i = 0; i < _capacity; i++) {
            _array[i].double_width_characters = nil;
        }
    }
    for (int i = 0; i < _capacity; i++) {
        iTermMetadataRelease(_array[i].lineMetadata);
    }
    free(_array);
}

- (void)setEntry:(int)i
  fromComponents:(NSArray *)components
externalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex {
    assert(i == _numEntries);
    assert(i < _capacity);
    _numEntries += 1;

    int j = 0;
    _array[i].continuation.code = [components[j++] unsignedShortValue];
    _array[i].continuation.backgroundColor = [components[j++] unsignedCharValue];
    _array[i].continuation.bgGreen = [components[j++] unsignedCharValue];
    _array[i].continuation.bgBlue = [components[j++] unsignedCharValue];
    _array[i].continuation.backgroundColorMode = [components[j++] unsignedCharValue];

    NSNumber *timestamp = components.count > j ? components[j++] : @0;
    iTermMetadataInit(&_array[i].lineMetadata,
                      timestamp.doubleValue,
                      eaIndex);
    _array[i].number_of_wrapped_lines = 0;
    if (_useDWCCache) {
        _array[i].double_width_characters = nil;
    }
}

- (void)setFirstIndex:(int)i {
    assert(i <= _numEntries);
    assert(i <= _capacity);

    _first = i;
}

- (LineBlockMetadataArray *)cowCopy {
#warning TODO: Actually impelement copy on write
    LineBlockMetadataArray *copy = [[LineBlockMetadataArray alloc] initWithCapacity:_capacity useDWCCache:_useDWCCache];
    for (int i = 0; i < _numEntries; i++) {
        [copy append:&_array[i]];
    }
    [copy setFirstIndex:_first];
    return copy;
}

- (const LineBlockMetadata *)metadataAtIndex:(int)i {
    assert(i >= 0 && i < _numEntries);
    return &_array[i];
}

- (iTermImmutableMetadata)immutableLineMetadataAtIndex:(int)i {
    iTermMetadataRetainAutorelease(_array[i].lineMetadata);
    return iTermMetadataMakeImmutable(_array[i].lineMetadata);
}

- (screen_char_t)lastContinuation {
    assert(_numEntries > 0);
    return _array[_numEntries - 1].continuation;
}

- (iTermExternalAttributeIndex *)lastExternalAttributeIndex {
    if (_numEntries == 0) {
        return nil;
    }
    return iTermMetadataGetExternalAttributesIndex(_array[_numEntries - 1].lineMetadata);
}

- (NSArray *)encodedArray {
    NSMutableArray *metadataArray = [NSMutableArray array];
    for (int i = 0; i < _numEntries; i++) {
        [metadataArray addObject:[@[ @(_array[i].continuation.code),
                                     @(_array[i].continuation.backgroundColor),
                                     @(_array[i].continuation.bgGreen),
                                     @(_array[i].continuation.bgBlue),
                                     @(_array[i].continuation.backgroundColorMode) ]
                                  arrayByAddingObjectsFromArray:iTermMetadataEncodeToArray(_array[i].lineMetadata)]];
    }
    return metadataArray;
}

#pragma mark - Mutation

- (void)append:(const LineBlockMetadata *)value {
    if (_numEntries + 1 >= _capacity) {
        [self increaseCapacityTo:_capacity * 2];
    }
    _numEntries += 1;
    [self setEntry:_numEntries - 1 value:value];
}

- (void)setEntry:(int)i value:(const LineBlockMetadata *)value {
    LineBlockMetadata *destination = (LineBlockMetadata *)&_array[i];

    iTermExternalAttributeIndex *index = iTermMetadataGetExternalAttributesIndex(value->lineMetadata);
    iTermExternalAttributeIndex *indexCopy = [index copy];
    iTermMetadataInit(&destination->lineMetadata,
                      value->lineMetadata.timestamp,
                      indexCopy);

    destination->continuation = value->continuation;
    destination->number_of_wrapped_lines = 0;
    destination->width_for_number_of_wrapped_lines = 0;
    if (_useDWCCache) {
        destination->double_width_characters = nil;
    }
    destination->width_for_double_width_characters_cache = 0;
}

- (void)append:(iTermImmutableMetadata)lineMetadata continuation:(screen_char_t)continuation {
    assert(_numEntries < _capacity);

    iTermMetadataAutorelease(_array[_numEntries].lineMetadata);
    _array[_numEntries].lineMetadata = iTermImmutableMetadataMutableCopy(lineMetadata);
    _array[_numEntries].continuation = continuation;
    _array[_numEntries].number_of_wrapped_lines = 0;

    _numEntries += 1;
}

- (void)appendToLastLine:(iTermImmutableMetadata *)metadataToAppend
          originalLength:(int)originalLength
        additionalLength:(int)additionalLength 
            continuation:(screen_char_t)continuation {
    assert(_numEntries > 0);
    iTermMetadataAppend(&_array[_numEntries - 1].lineMetadata,
                        originalLength,
                        metadataToAppend,
                        additionalLength);
    _array[_numEntries - 1].continuation = continuation;
    _array[_numEntries - 1].number_of_wrapped_lines = 0;
    if (_useDWCCache) {
        // TODO: Would be nice to add on to the index set instead of deleting it.
        _array[_numEntries - 1].double_width_characters = nil;
    }
}

- (void)increaseCapacityTo:(int)newCapacity {
    if (newCapacity <= _capacity) {
        return;
    }
    const int formerCapacity = _capacity;
    _capacity = newCapacity;
    _capacity = MAX(1, _capacity);
    _array = (LineBlockMetadata *)iTermZeroingRealloc((void *)_array,
                                                         formerCapacity,
                                                         _capacity,
                                                         sizeof(LineBlockMetadata));
}

- (LineBlockMetadata *)mutableMetadataAtIndex:(int)i {
    return &_array[i];
}

- (void)removeLast {
    assert(_numEntries > 0);
    _numEntries -= 1;
    _array[_numEntries].number_of_wrapped_lines = 0;
    if (_useDWCCache) {
        _array[_numEntries].double_width_characters = nil;
        iTermMetadataSetExternalAttributes(&_array[_numEntries].lineMetadata, nil);
    }
    if (_numEntries == _first) {
        [self reset];
    }
}

- (void)eraseLastLineCache {
    if (_numEntries == 0) {
        return;
    }
    _array[_numEntries - 1].number_of_wrapped_lines = 0;
    if (_useDWCCache) {
        _array[_numEntries - 1].double_width_characters = nil;
    }
}

- (void)eraseFirstLineCache {
    _array[_first].width_for_number_of_wrapped_lines = 0;
    _array[_first].number_of_wrapped_lines = 0;
}

- (void)setLastExternalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex {
    assert(_numEntries > 0);
    iTermMetadataSetExternalAttributes(&_array[_numEntries - 1].lineMetadata,
                                       eaIndex);

}

- (void)removeFirst {
    [self removeFirst:1];
}

- (void)removeFirst:(int)n {
    for (int i = 0; i < n; i++) {
        assert(_numEntries >= _first);
        _array[_first].number_of_wrapped_lines = 0;
        if (_useDWCCache) {
            _array[_first].double_width_characters = nil;
        }
        iTermMetadataSetExternalAttributes(&_array[_first].lineMetadata, nil);
        _first += 1;
        assert(_first <= _numEntries);
    }
}

- (void)reset {
    for (int i = 0; i < _numEntries; i++) {
        iTermMetadataSetExternalAttributes(&_array[i].lineMetadata, nil);
        _array[i].double_width_characters = nil;
    }
    _numEntries = 0;
    _first = 0;
}

@end
