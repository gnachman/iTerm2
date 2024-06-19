//
//  LineBlockMetadataArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/19/24.
//

#import "LineBlockMetadataArray.h"

#import "iTermMalloc.h"

@interface CopyOnWriteRefCount: NSObject {
    os_unfair_lock _lock;
    int _count;
}
- (CopyOnWriteRefCount *)increment;
- (CopyOnWriteRefCount *)decrement;
- (void)ifPluralDecrementThen:(void (^NS_NOESCAPE)(void))closure;
@end

@implementation CopyOnWriteRefCount

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _count = 1;
    }
    return self;
}

- (CopyOnWriteRefCount *)increment {
    os_unfair_lock_lock(&_lock);
    _count += 1;
    os_unfair_lock_unlock(&_lock);
    return self;
}

- (CopyOnWriteRefCount *)decrement {
    os_unfair_lock_lock(&_lock);
    _count -= 1;
    os_unfair_lock_unlock(&_lock);
    return self;
}

- (void)ifPluralDecrementThen:(void (^NS_NOESCAPE)(void))closure {
    os_unfair_lock_lock(&_lock);
    if (_count > 1) {
        _count -= 1;
        closure();
    }
    os_unfair_lock_unlock(&_lock);
}

@end

@interface LineBlockMetadataArrayGuts: NSObject {
@public
    LineBlockMetadata *_array;
    int _numEntries;  // Inclusive of _first.
    int _first;
    BOOL _useDWCCache;
    int _capacity;
}

- (instancetype)copy;

@end

@implementation LineBlockMetadataArrayGuts

- (instancetype)copy {
    LineBlockMetadataArrayGuts *copy = [[LineBlockMetadataArrayGuts alloc] init];
    copy->_array = (LineBlockMetadata *)iTermCalloc(sizeof(LineBlockMetadata), _capacity);
    copy->_numEntries = _numEntries;
    copy->_first = _first;
    copy->_useDWCCache = _useDWCCache;
    copy->_capacity = _capacity;

    for (int i = 0; i < _numEntries; i++) {
        const LineBlockMetadata *value = &_array[i];
        LineBlockMetadata *destination = &copy->_array[i];

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

    return copy;
}

- (void)dealloc {
    if (!_array) {
        return;
    }
    if (_useDWCCache) {
        for (int i = 0; i < _numEntries; i++) {
            _array[i].double_width_characters = nil;
        }
    }
    for (int i = 0; i < _numEntries; i++) {
        iTermMetadataRelease(_array[i].lineMetadata);
    }
    free(_array);
    _array = (LineBlockMetadata *)0xdeadbeef;
}

@end

@implementation LineBlockMetadataArray {
    LineBlockMetadataArrayGuts *_guts;
    CopyOnWriteRefCount *_ref;
}

- (instancetype)initWithCapacity:(int)capacity useDWCCache:(BOOL)useDWCCache {
    self = [super init];
    if (self) {
        _ref = [[CopyOnWriteRefCount alloc] init];
        _guts = [[LineBlockMetadataArrayGuts alloc] init];
        _guts->_useDWCCache = useDWCCache;
        _guts->_array = (LineBlockMetadata *)iTermCalloc(sizeof(LineBlockMetadata), capacity);
        _guts->_capacity = capacity;
    }
    return self;
}

- (instancetype)initWithGuts:(LineBlockMetadataArrayGuts *)guts ref:(CopyOnWriteRefCount *)ref {
    self = [super init];
    if (self) {
        _ref = ref;
        [ref increment];
        _guts = guts;
    }
    return self;
}

- (void)dealloc {
    [_ref decrement];
}

- (BOOL)useDWCCache {
    return _guts->_useDWCCache;
}

- (int)capacity {
    return _guts->_capacity;
}

- (int)numEntries {
    return _guts->_numEntries;
}

- (int)first {
    return _guts->_first;
}

- (void)setEntry:(int)i
  fromComponents:(NSArray *)components
externalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex {
    assert(i == _guts->_numEntries);
    assert(i < _guts->_capacity);
    _guts->_numEntries += 1;

    int j = 0;
    _guts->_array[i].continuation.code = [components[j++] unsignedShortValue];
    _guts->_array[i].continuation.backgroundColor = [components[j++] unsignedCharValue];
    _guts->_array[i].continuation.bgGreen = [components[j++] unsignedCharValue];
    _guts->_array[i].continuation.bgBlue = [components[j++] unsignedCharValue];
    _guts->_array[i].continuation.backgroundColorMode = [components[j++] unsignedCharValue];

    NSNumber *timestamp = components.count > j ? components[j++] : @0;
    iTermMetadataInit(&_guts->_array[i].lineMetadata,
                      timestamp.doubleValue,
                      eaIndex);
    _guts->_array[i].number_of_wrapped_lines = 0;
    if (_guts->_useDWCCache) {
        _guts->_array[i].double_width_characters = nil;
    }
}

- (void)setFirstIndex:(int)i {
    assert(i <= _guts->_numEntries);
    assert(i <= _guts->_capacity);

    _guts->_first = i;
}

- (LineBlockMetadataArray *)cowCopy {
    return [[LineBlockMetadataArray alloc] initWithGuts:_guts ref:_ref];
}

- (void)willMutate {
    [_ref ifPluralDecrementThen:^{
        _guts = [_guts copy];
        _ref = [[CopyOnWriteRefCount alloc] init];
    }];
}

- (const LineBlockMetadata *)metadataAtIndex:(int)i {
    assert(i >= 0 && i < _guts->_numEntries);
    return &_guts->_array[i];
}

- (iTermImmutableMetadata)immutableLineMetadataAtIndex:(int)i {
    iTermMetadataRetainAutorelease(_guts->_array[i].lineMetadata);
    return iTermMetadataMakeImmutable(_guts->_array[i].lineMetadata);
}

- (screen_char_t)lastContinuation {
    assert(_guts->_numEntries > 0);
    return _guts->_array[_guts->_numEntries - 1].continuation;
}

- (iTermExternalAttributeIndex *)lastExternalAttributeIndex {
    if (_guts->_numEntries == 0) {
        return nil;
    }
    return iTermMetadataGetExternalAttributesIndex(_guts->_array[_guts->_numEntries - 1].lineMetadata);
}

- (NSArray *)encodedArray {
    NSMutableArray *metadataArray = [NSMutableArray array];
    for (int i = 0; i < _guts->_numEntries; i++) {
        [metadataArray addObject:[@[ @(_guts->_array[i].continuation.code),
                                     @(_guts->_array[i].continuation.backgroundColor),
                                     @(_guts->_array[i].continuation.bgGreen),
                                     @(_guts->_array[i].continuation.bgBlue),
                                     @(_guts->_array[i].continuation.backgroundColorMode) ]
                                  arrayByAddingObjectsFromArray:iTermMetadataEncodeToArray(_guts->_array[i].lineMetadata)]];
    }
    return metadataArray;
}

#pragma mark - Mutation

- (void)append:(const LineBlockMetadata *)value {
    if (_guts->_numEntries + 1 >= _guts->_capacity) {
        [self increaseCapacityTo:_guts->_capacity * 2];
    }
    _guts->_numEntries += 1;
    [self setEntry:_guts->_numEntries - 1 value:value];
}

- (void)setEntry:(int)i value:(const LineBlockMetadata *)value {
    LineBlockMetadata *destination = (LineBlockMetadata *)&_guts->_array[i];

    iTermExternalAttributeIndex *index = iTermMetadataGetExternalAttributesIndex(value->lineMetadata);
    iTermExternalAttributeIndex *indexCopy = [index copy];
    iTermMetadataInit(&destination->lineMetadata,
                      value->lineMetadata.timestamp,
                      indexCopy);

    destination->continuation = value->continuation;
    destination->number_of_wrapped_lines = 0;
    destination->width_for_number_of_wrapped_lines = 0;
    if (_guts->_useDWCCache) {
        destination->double_width_characters = nil;
    }
    destination->width_for_double_width_characters_cache = 0;
}

- (void)append:(iTermImmutableMetadata)lineMetadata continuation:(screen_char_t)continuation {
    assert(_guts->_numEntries < _guts->_capacity);

    iTermMetadataAutorelease(_guts->_array[_guts->_numEntries].lineMetadata);
    _guts->_array[_guts->_numEntries].lineMetadata = iTermImmutableMetadataMutableCopy(lineMetadata);
    _guts->_array[_guts->_numEntries].continuation = continuation;
    _guts->_array[_guts->_numEntries].number_of_wrapped_lines = 0;

    _guts->_numEntries += 1;
}

- (void)appendToLastLine:(iTermImmutableMetadata *)metadataToAppend
          originalLength:(int)originalLength
        additionalLength:(int)additionalLength 
            continuation:(screen_char_t)continuation {
    assert(_guts->_numEntries > 0);
    iTermMetadataAppend(&_guts->_array[_guts->_numEntries - 1].lineMetadata,
                        originalLength,
                        metadataToAppend,
                        additionalLength);
    _guts->_array[_guts->_numEntries - 1].continuation = continuation;
    _guts->_array[_guts->_numEntries - 1].number_of_wrapped_lines = 0;
    if (_guts->_useDWCCache) {
        // TODO: Would be nice to add on to the index set instead of deleting it.
        _guts->_array[_guts->_numEntries - 1].double_width_characters = nil;
    }
}

- (void)increaseCapacityTo:(int)newCapacity {
    if (newCapacity <= _guts->_capacity) {
        return;
    }
    const int formerCapacity = _guts->_capacity;
    _guts->_capacity = newCapacity;
    _guts->_capacity = MAX(1, _guts->_capacity);
    _guts->_array = (LineBlockMetadata *)iTermZeroingRealloc((void *)_guts->_array,
                                                         formerCapacity,
                                                      _guts->_capacity,
                                                         sizeof(LineBlockMetadata));
}

- (LineBlockMetadata *)mutableMetadataAtIndex:(int)i {
    return &_guts->_array[i];
}

- (void)removeLast {
    assert(_guts->_numEntries > 0);
    _guts->_numEntries -= 1;
    _guts->_array[_guts->_numEntries].number_of_wrapped_lines = 0;
    if (_guts->_useDWCCache) {
        _guts->_array[_guts->_numEntries].double_width_characters = nil;
        iTermMetadataSetExternalAttributes(&_guts->_array[_guts->_numEntries].lineMetadata, nil);
    }
    if (_guts->_numEntries == _guts->_first) {
        [self reset];
    }
}

- (void)eraseLastLineCache {
    if (_guts->_numEntries == 0) {
        return;
    }
    _guts->_array[_guts->_numEntries - 1].number_of_wrapped_lines = 0;
    if (_guts->_useDWCCache) {
        _guts->_array[_guts->_numEntries - 1].double_width_characters = nil;
    }
}

- (void)eraseFirstLineCache {
    _guts->_array[_guts->_first].width_for_number_of_wrapped_lines = 0;
    _guts->_array[_guts->_first].number_of_wrapped_lines = 0;
}

- (void)setLastExternalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex {
    assert(_guts->_numEntries > 0);
    iTermMetadataSetExternalAttributes(&_guts->_array[_guts->_numEntries - 1].lineMetadata,
                                       eaIndex);

}

- (void)removeFirst {
    [self removeFirst:1];
}

- (void)removeFirst:(int)n {
    for (int i = 0; i < n; i++) {
        assert(_guts->_numEntries >= _guts->_first);
        _guts->_array[_guts->_first].number_of_wrapped_lines = 0;
        if (_guts->_useDWCCache) {
            _guts->_array[_guts->_first].double_width_characters = nil;
        }
        iTermMetadataSetExternalAttributes(&_guts->_array[_guts->_first].lineMetadata, nil);
        _guts->_first += 1;
        assert(_guts->_first <= _guts->_numEntries);
    }
}

- (void)reset {
    for (int i = 0; i < _guts->_numEntries; i++) {
        iTermMetadataSetExternalAttributes(&_guts->_array[i].lineMetadata, nil);
        _guts->_array[i].double_width_characters = nil;
    }
    _guts->_numEntries = 0;
    _guts->_first = 0;
}

@end
