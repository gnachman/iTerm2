//
//  iTermPreferencesSearch.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/28/19.
//

#import "iTermPreferencesSearch.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSSet+iTerm.h"
#import "NSStringITerm.h"
#import "iTermAdvancedSettingsModel.h"

@implementation iTermPreferencesSearchDocument

+ (instancetype)documentWithDisplayName:(NSString *)displayName
                             identifier:(NSString *)identifier
                         keywordPhrases:(NSArray<NSString *> *)keywordPhrases
                           profileTypes:(ProfileType)profileTypes {
    return [[iTermPreferencesSearchDocument alloc] initWithDisplayName:displayName
                                                            identifier:identifier
                                                        keywordPhrases:keywordPhrases
                                                          profileTypes:profileTypes];
}

- (instancetype)initWithDisplayName:(NSString *)displayName
                         identifier:(NSString *)identifier
                     keywordPhrases:(NSArray<NSString *> *)keywordPhrases
                       profileTypes:(ProfileType)profileTypes {
    self = [super init];
    if (self) {
        static NSUInteger nextDocId;
        _docid = @(nextDocId++);
        _displayName = [displayName copy];
        _identifier = [identifier copy];
        _keywordPhrases = [keywordPhrases copy];
        _profileTypes = profileTypes;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p docid=%@ identifier=%@ displayName=%@>", self.class, self, self.docid, self.identifier, self.displayName];
}

- (NSArray<NSString *> *)indexablePhrases {
    return [_keywordPhrases ?: @[] arrayByAddingObject:_displayName];
}

- (NSArray<NSString *> *)allKeywords {
    NSArray *phrases = [self indexablePhrases];
    return [[phrases mapWithBlock:^id(NSString *phrase) {
        return phrase.it_normalizedTokens;
    }] flattenedArray];
}

- (NSArray<NSString *> *)allStems {
    return [self.allKeywords mapWithBlock:^id _Nullable(NSString *keyword) {
        return [keyword it_stem];
    }];
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

// Phrases are arrays of normalized tokens.
- (BOOL)containsPhrases:(NSArray<NSArray<NSString *> *> *)phrases {
    return [phrases allWithBlock:^BOOL(NSArray<NSString *> *phrase) {
        return [self containsPhrase:phrase];
    }];
}

- (BOOL)containsPhrase:(NSArray<NSString *> *)phrase {
    return [self.indexablePhrases anyWithBlock:^BOOL(NSString *haystack) {
        return [[haystack it_normalizedTokens] it_containsSubarray:phrase];
    }];
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
@property (nonatomic) NSInteger index;  // NSNotFound means it represents an empty token and can be ignored.
@property (nonatomic, readonly) NSSet<NSNumber *> *docIDs;

- (instancetype)initWithToken:(NSString *)token index:(NSInteger)index NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)advance;
- (void)unionDocIDs:(NSSet<NSNumber *> *)docIDs;
@end

@implementation iTermPreferencesSearchCursor {
    NSMutableSet<NSNumber *> *_docIDs;
}

- (instancetype)initWithCursors:(NSArray<iTermPreferencesSearchCursor *> *)cursors {
    self = [self initWithToken:cursors[0].keyword.keyword
                         index:0];
    if (self) {
        NSMutableSet *docIDs = [NSMutableSet set];
        [cursors enumerateObjectsUsingBlock:^(iTermPreferencesSearchCursor *cursor, NSUInteger idx, BOOL * _Nonnull stop) {
            [docIDs unionSet:cursor.docIDs];
        }];
        _docIDs = docIDs;
    }
    return self;
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
    NSMutableArray<iTermPreferencesSearchIndexEntry *> *_keywordIndex;
    NSMutableArray<iTermPreferencesSearchIndexEntry *> *_stemIndex;
    NSMutableDictionary<NSNumber *, iTermPreferencesSearchDocument *> *_docs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _keywordIndex = [NSMutableArray array];
        _stemIndex = [NSMutableArray array];
        _docs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dump {
    NSLog(@"KEYWORDS:");
    [_keywordIndex enumerateObjectsUsingBlock:^(iTermPreferencesSearchIndexEntry * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        // index: keyword -> ([docid: identifier], ...)
        NSLog(@"%@: %@ -> %@", @(idx), obj.keyword, [[obj.documents mapWithBlock:^id(iTermPreferencesSearchDocument *doc) {
            return [NSString stringWithFormat:@"[%@: %@]", doc.docid, doc.identifier];
        }] componentsJoinedByString:@", "]);
    }];
    NSLog(@"STEMS:");
    [_stemIndex enumerateObjectsUsingBlock:^(iTermPreferencesSearchIndexEntry * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        // index: stem -> ([docid: identifier], ...)
        NSLog(@"%@: %@ -> %@", @(idx), obj.keyword, [[obj.documents mapWithBlock:^id(iTermPreferencesSearchDocument *doc) {
            return [NSString stringWithFormat:@"[%@: %@]", doc.docid, doc.identifier];
        }] componentsJoinedByString:@", "]);
    }];
}

- (void)addDocumentToIndex:(iTermPreferencesSearchDocument *)document {
    if (document.profileTypes == ProfileTypeBrowser && ![iTermAdvancedSettingsModel browserProfiles]) {
        return;
    }
    for (NSString *keyword in [NSSet setWithArray:document.allKeywords]) {
        [self addToken:keyword inDocument:document toIndex:_keywordIndex];
    }
    for (NSString *stem in [NSSet setWithArray:document.allStems]) {
        [self addToken:stem inDocument:document toIndex:_stemIndex];
    }
    _docs[document.docid] = document;
}

- (void)addToken:(NSString *)token
      inDocument:(iTermPreferencesSearchDocument *)document
         toIndex:(NSMutableArray<iTermPreferencesSearchIndexEntry *> *)index {
    iTermPreferencesSearchIndexEntry *entry = [[iTermPreferencesSearchIndexEntry alloc] initWithKeyword:token
                                                                                               document:document];
    NSInteger i = [index indexOfObject:entry
                              inSortedRange:NSMakeRange(0, index.count)
                                   options:(NSBinarySearchingInsertionIndex | NSBinarySearchingLastEqual)
                           usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return [obj1 compare:obj2];
    }];
    if (i > 0 && [index[i - 1].keyword isEqualToString:token]) {
        iTermPreferencesSearchIndexEntry *entry = index[i - 1];
        [entry addDocument:document];
        return;
    }
    [index insertObject:entry atIndex:i];
}


- (iTermPreferencesSearchDocument *)documentWithKey:(NSString *)key {
    for (NSNumber *docid in _docs) {
        iTermPreferencesSearchDocument *doc = _docs[docid];
        if ([doc.identifier isEqual:key]) {
            return doc;
        }
    }
    return nil;
}

- (NSArray<iTermPreferencesSearchDocument *> *)documentsMatchingQuery:(NSString *)query {
    NSString *trimmedQuery = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    iTermTuple<NSArray<NSString *> *, NSString *> *tuple = [trimmedQuery queryBySplittingLiteralPhrases];
    NSArray<NSString *> *rawTokens = [trimmedQuery it_normalizedTokens];
    NSArray<NSString *> *stemmedTokens = [rawTokens mapWithBlock:^id _Nullable(NSString *token) {
        return token.it_stem;
    }];

    NSArray<iTermPreferencesSearchCursor *> *kwCursors = [self cursorsForQueryTokens:rawTokens
                                                                         searchIndex:_keywordIndex
                                                                         prefixMatch:YES];
    NSArray<iTermPreferencesSearchCursor *> *stemCursors = [self cursorsForQueryTokens:stemmedTokens
                                                                           searchIndex:_stemIndex
                                                                           prefixMatch:YES];
    NSArray<iTermPreferencesSearchCursor *> *cursors = [[kwCursors zip:stemCursors] mapWithBlock:^id _Nullable(iTermTuple * tuple) {
        return [[iTermPreferencesSearchCursor alloc] initWithCursors:@[tuple.firstObject, tuple.secondObject]];
    }];

    NSSet<NSNumber *> *docIDs = [self intersectCursorDocIDs:cursors];
    if (tuple.firstObject.count) {
        docIDs = [self documentsWithLiteralPhrases:tuple.firstObject fromDocIDs:docIDs];
    }
    return [self documentsSortedByDisplayNameWithDocIDs:docIDs];
}

- (NSSet<NSNumber *> *)documentsWithLiteralPhrases:(NSArray<NSString *> *)phrases fromDocIDs:(NSSet<NSNumber *> *)docIDs {
    NSArray<NSArray<NSString *> *> *normalizedPhrases = [phrases mapWithBlock:^id _Nullable(NSString *phrase) {
        return [phrase it_normalizedTokens];
    }];
    return [docIDs filteredSetUsingBlock:^BOOL(NSNumber *docID) {
        iTermPreferencesSearchDocument *doc = self->_docs[docID];
        return [doc containsPhrases:normalizedPhrases];
    }];
}

- (NSArray<iTermPreferencesSearchCursor *> *)cursorsForQueryTokens:(NSArray<NSString *> *)tokens
                                                       searchIndex:(NSArray<iTermPreferencesSearchIndexEntry *> *)searchIndex
                                                       prefixMatch:(BOOL)prefixMatch {
    NSArray<iTermPreferencesSearchCursor *> *cursors = [tokens mapWithBlock:^id(NSString *token) {
        iTermPreferencesSearchCursor *cursor = [[iTermPreferencesSearchCursor alloc] initWithToken:token index:NSNotFound];
        if (token.length == 0) {
            return cursor;
        }
        cursor.index = [self firstIndexForKeyword:cursor.keyword inSearchIndex:searchIndex];
        return cursor;
    }];

    for (iTermPreferencesSearchCursor *cursor in cursors) {
        while ([self cursorIsLive:cursor inSearchIndex:searchIndex prefixMatch:prefixMatch]) {
            [cursor unionDocIDs:searchIndex[cursor.index].docids];
            [cursor advance];
        }
    }
    return cursors;
}

- (NSSet<NSNumber *> *)intersectCursorDocIDs:(NSArray<iTermPreferencesSearchCursor *> *)cursors {
    NSSet<NSNumber *> *docids = [self commonDocIDsAmongCursors:cursors];
    NSDictionary<NSString *, NSArray<NSNumber *> *> *identifierToDocids = [docids.allObjects classifyWithBlock:^id(NSNumber *docid) {
        return self->_docs[docid].identifier;
    }];
    docids = [NSSet setWithArray:[identifierToDocids.allValues mapWithBlock:^id(NSArray<NSNumber *> *docids) {
        return docids.firstObject;
    }]];
    return docids;
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
- (BOOL)cursorIsLive:(iTermPreferencesSearchCursor *)cursor
       inSearchIndex:(NSArray<iTermPreferencesSearchKeyword *> *)searchIndex
         prefixMatch:(BOOL)prefixMatch {
    if (cursor.index == NSNotFound) {
        return NO;
    }
    if (cursor.index == searchIndex.count) {
        return NO;
    }
    NSString *const indexWord = searchIndex[cursor.index].keyword;
    if (prefixMatch) {
        return [indexWord hasPrefix:cursor.keyword.keyword];
    } else {
        return [indexWord isEqualToString:cursor.keyword.keyword];
    }
}

- (NSInteger)firstIndexForKeyword:(iTermPreferencesSearchKeyword *)keyword
                    inSearchIndex:(NSArray<iTermPreferencesSearchKeyword *> *)searchIndex {
    NSInteger index = [searchIndex indexOfObject:keyword
                                   inSortedRange:NSMakeRange(0, searchIndex.count)
                                         options:NSBinarySearchingInsertionIndex
                                 usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                                  return [obj1 compare:obj2];
                              }];
    if (index > 0) {
        if ([keyword.keyword isEqualToString:searchIndex[index - 1].keyword]) {
            return index - 1;
        }
    }
    return index;
}

@end
