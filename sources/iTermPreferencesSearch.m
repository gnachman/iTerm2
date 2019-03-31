//
//  iTermPreferencesSearch.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/28/19.
//

#import "iTermPreferencesSearch.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermPreferencesSearchDocument

+ (instancetype)documentWithDisplayName:(NSString *)displayName
                             identifier:(NSString *)identifier
                         keywordPhrases:(NSArray<NSString *> *)keywordPhrases {
    return [[iTermPreferencesSearchDocument alloc] initWithDisplayName:displayName
                                                            identifier:identifier
                                                        keywordPhrases:keywordPhrases];
}

- (instancetype)initWithDisplayName:(NSString *)displayName
                         identifier:(NSString *)identifier
                     keywordPhrases:(NSArray<NSString *> *)keywordPhrases {
    self = [super init];
    if (self) {
        static NSUInteger nextDocId;
        _docid = @(nextDocId++);
        _displayName = [displayName copy];
        _identifier = [identifier copy];
        _keywordPhrases = [keywordPhrases copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p docid=%@ identifier=%@ displayName=%@>", self.class, self, self.docid, self.identifier, self.displayName];
}

- (NSArray<NSString *> *)allKeywords {
    NSArray *phrases = [_keywordPhrases ?: @[] arrayByAddingObject:_displayName];
    return [[phrases mapWithBlock:^id(NSString *phrase) {
        return phrase.it_normalizedTokens;
    }] flattenedArray];
}

- (BOOL)isEqual:(id)object {
    iTermPreferencesSearchDocument *other = [iTermPreferencesSearchDocument castFrom:object];
    if (!other) {
        return NO;
    }
    return [other.docid isEqual:self.docid];
}

- (NSUInteger)hash {
    return self.docid.hash;
}

- (NSComparisonResult)compare:(id)object {
    iTermPreferencesSearchDocument *other = [iTermPreferencesSearchDocument castFrom:object];
    return [self.docid compare:other.docid];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

@interface iTermPreferencesSearchKeyword : NSObject
@property (nonatomic, copy) NSString *keyword;

- (instancetype)initWithKeyword:(NSString *)keyword NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation iTermPreferencesSearchKeyword

- (instancetype)initWithKeyword:(NSString *)keyword {
    self = [super init];
    if (self) {
        _keyword = [keyword copy];
    }
    return self;
}

- (NSComparisonResult)compare:(id)other {
    NSString *otherKeyword = [other keyword];
    return [_keyword compare:otherKeyword];
}

@end

@interface iTermPreferencesSearchIndexEntry : iTermPreferencesSearchKeyword
@property (nonatomic, strong) NSArray<iTermPreferencesSearchDocument *> *documents;
@property (nonatomic, readonly) NSSet<NSNumber *> *docids;

- (instancetype)initWithKeyword:(NSString *)keyword document:(iTermPreferencesSearchDocument *)document NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithKeyword:(NSString *)keyword NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)addDocument:(iTermPreferencesSearchDocument *)document;
@end

@implementation iTermPreferencesSearchIndexEntry {
    NSMutableArray<iTermPreferencesSearchDocument *> *_documents;
    NSMutableSet<NSNumber *> *_docids;
}

- (instancetype)initWithKeyword:(NSString *)keyword document:(iTermPreferencesSearchDocument *)document {
    self = [super initWithKeyword:keyword];
    if (self) {
        _documents = [NSMutableArray arrayWithObject:document];
        _docids = [NSMutableSet setWithObject:document.docid];
    }
    return self;
}

- (void)addDocument:(iTermPreferencesSearchDocument *)document {
    [_documents addObject:document];
    [_docids addObject:document.docid];
}

@end

@interface iTermPreferencesSearchCursor : NSObject
@property (nonatomic, readonly) iTermPreferencesSearchKeyword *keyword;
@property (nonatomic) NSInteger index;
@property (nonatomic, readonly) NSSet<NSNumber *> *docIDs;

- (instancetype)initWithToken:(NSString *)token index:(NSInteger)index NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)advance;
- (void)unionDocIDs:(NSSet<NSNumber *> *)docIDs;
@end

@implementation iTermPreferencesSearchCursor {
    NSMutableSet<NSNumber *> *_docIDs;
}

- (instancetype)initWithToken:(NSString *)token index:(NSInteger)index {
    self = [super init];
    if (self) {
        _keyword = [[iTermPreferencesSearchKeyword alloc] initWithKeyword:token];
        _index = index;
        _docIDs = [NSMutableSet set];
    }
    return self;
}

- (void)advance {
    _index++;
}

- (void)unionDocIDs:(NSSet<NSNumber *> *)docIDs {
    [_docIDs unionSet:docIDs];
}

@end

@implementation iTermPreferencesSearchEngine {
    NSMutableArray<iTermPreferencesSearchIndexEntry *> *_index;
    NSMutableDictionary<NSNumber *, iTermPreferencesSearchDocument *> *_docs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _index = [NSMutableArray array];
        _docs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dump {
    [_index enumerateObjectsUsingBlock:^(iTermPreferencesSearchIndexEntry * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        // index: keyword -> ([docid: identifier], ...)
        NSLog(@"%@: %@ -> %@", @(idx), obj.keyword, [[obj.documents mapWithBlock:^id(iTermPreferencesSearchDocument *doc) {
            return [NSString stringWithFormat:@"[%@: %@]", doc.docid, doc.identifier];
        }] componentsJoinedByString:@", "]);
    }];
}

- (void)addDocumentToIndex:(iTermPreferencesSearchDocument *)document {
    for (NSString *keyword in document.allKeywords) {
        iTermPreferencesSearchIndexEntry *entry = [[iTermPreferencesSearchIndexEntry alloc] initWithKeyword:keyword document:document];
        NSInteger index = [_index indexOfObject:entry
                                  inSortedRange:NSMakeRange(0, _index.count)
                                        options:(NSBinarySearchingInsertionIndex | NSBinarySearchingLastEqual)
                             usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                                 return [obj1 compare:obj2];
                             }];
        if (index > 0 && [_index[index - 1].keyword isEqualToString:keyword]) {
            iTermPreferencesSearchIndexEntry *entry = _index[index - 1];
            [entry addDocument:document];
            continue;
        }
        [_index insertObject:entry atIndex:index];
    }
    _docs[document.docid] = document;
}

- (NSArray<iTermPreferencesSearchDocument *> *)documentsMatchingQuery:(NSString *)query {
    NSString *trimmedQuery = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *tokens = [trimmedQuery it_normalizedTokens];
    NSArray<iTermPreferencesSearchCursor *> *cursors = [tokens mapWithBlock:^id(NSString *token) {
        if (token.length == 0) {
            return nil;
        }
        iTermPreferencesSearchCursor *cursor = [[iTermPreferencesSearchCursor alloc] initWithToken:token index:NSNotFound];
        cursor.index = [self firstIndexForKeyword:cursor.keyword];
        return cursor;
    }];
    if (cursors.count == 0) {
        return @[];
    }

    for (iTermPreferencesSearchCursor *cursor in cursors) {
        while ([self cursorIsLive:cursor]) {
            [cursor unionDocIDs:_index[cursor.index].docids];
            [cursor advance];
        }
    }

    NSSet<NSNumber *> *docids = [self commonDocIDsAmongCursors:cursors];
    NSDictionary<NSString *, NSArray<NSNumber *> *> *identifierToDocids = [docids.allObjects classifyWithBlock:^id(NSNumber *docid) {
        return self->_docs[docid].identifier;
    }];
    docids = [NSSet setWithArray:[identifierToDocids.allValues mapWithBlock:^id(NSArray<NSNumber *> *docids) {
        return docids.firstObject;
    }]];
    return [self documentsSortedByDisplayNameWithDocIDs:docids];
}

- (NSArray<iTermPreferencesSearchDocument *> *)documentsSortedByDisplayNameWithDocIDs:(NSSet<NSNumber *> *)docids {
    return [[docids.allObjects mapWithBlock:^id(NSNumber *docid) {
        return self->_docs[docid];
    }] sortedArrayUsingComparator:^NSComparisonResult(iTermPreferencesSearchDocument * _Nonnull doc1, iTermPreferencesSearchDocument * _Nonnull doc2) {
        if (doc1.queryIndependentScore != doc2.queryIndependentScore) {
            return [@(doc2.queryIndependentScore) compare:@(doc1.queryIndependentScore)];
        }
        return [doc1.displayName localizedCaseInsensitiveCompare:doc2.displayName];
    }];
}

- (NSSet<NSNumber *> *)commonDocIDsAmongCursors:(NSArray<iTermPreferencesSearchCursor *> *)cursors {
    NSMutableSet<NSNumber *> *docids = [cursors.firstObject.docIDs mutableCopy];
    for (iTermPreferencesSearchCursor *cursor in [cursors subarrayFromIndex:1]) {
        [docids intersectSet:cursor.docIDs];
    }
    return docids;
}

// Cursor refers to valid index that has the cursor's keyword as its prefix.
- (BOOL)cursorIsLive:(iTermPreferencesSearchCursor *)cursor {
    if (cursor.index == _index.count) {
        return NO;
    }
    NSString *const indexWord = _index[cursor.index].keyword;
    return [indexWord hasPrefix:cursor.keyword.keyword];
}

- (NSInteger)firstIndexForKeyword:(iTermPreferencesSearchKeyword *)keyword {
    NSArray<iTermPreferencesSearchKeyword *> *keywords = (NSArray<iTermPreferencesSearchKeyword *> *)_index;
    NSInteger index = [keywords indexOfObject:keyword
                                inSortedRange:NSMakeRange(0, _index.count)
                                      options:NSBinarySearchingInsertionIndex
                              usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                                  return [obj1 compare:obj2];
                              }];
    if (index > 0) {
        if ([keyword.keyword isEqualToString:keywords[index - 1].keyword]) {
            return index - 1;
        }
    }
    return index;
}

@end
