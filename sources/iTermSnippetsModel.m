//
//  iTermSnippetsModel.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import "iTermSnippetsModel.h"
#import "iTermNotificationCenter+Protected.h"
#import "iTermPreferences.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@implementation iTermSnippet

- (instancetype)initWithTitle:(NSString *)title
                        value:(NSString *)value
                         guid:(NSString *)guid
     useCompatibilityEscaping:(BOOL)useCompatibilityEscaping {
    if (self) {
        _title = [title copy];
        _value = [value copy];
        _guid = guid;
        _useCompatibilityEscaping = useCompatibilityEscaping;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary index:(NSInteger)i {
    NSString *title = dictionary[@"title"] ?: @"";
    NSString *value = dictionary[@"value"] ?: @"";
    // The fallback GUID is a migration path for pre-3.4.5 versions which did not serialize an
    // identifier. That was a bad idea because actions need a way to refer to an item since titles
    // could be ambiguous. The key thing about it is that it's stable. You can create new actions,
    // and they'll have GUIDs, even if your snippet table doesn't get re-written. If you edit your
    // snippets then they will all be assigned GUIDs. The only problem is if you downgrade your
    // actions will be broken since they'll continue to have GUIDs but older versions expect them to
    // have titles (and it'll probably crash. Don't downgrade).
    return [self initWithTitle:title
                         value:value
                          guid:dictionary[@"guid"] ?: [[@[ [@(i) stringValue], title, value ] hashWithSHA256] it_hexEncoded]
      useCompatibilityEscaping:[dictionary[@"version"] intValue] == 0];
}

- (NSDictionary *)dictionaryValue {
    return @{ @"title": _title ?: @"",
              @"value": _value ?: @"",
              @"guid": _guid,
              @"version": _useCompatibilityEscaping ? @0 : @1,
    };
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    iTermSnippet *other = [iTermSnippet castFrom:object];
    if (!other) {
        return NO;
    }
    return [self.guid isEqual:other.guid];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p title=%@ value=%@ guid=%@ compat=%@>",
            NSStringFromClass([self class]),
            self,
            _title,
            _value,
            _guid,
            @(_useCompatibilityEscaping)];
}

- (NSString *)trimmedValue:(NSInteger)maxLength {
    return [self.value ellipsizedDescriptionNoLongerThan:maxLength];
}

- (NSString *)trimmedTitle:(NSInteger)maxLength {
    return [self.title ellipsizedDescriptionNoLongerThan:maxLength];
}

- (BOOL)titleEqualsValueUpToLength:(NSInteger)maxLength {
    return [[self trimmedTitle:maxLength] isEqualToString:[self trimmedValue:maxLength]];
}

- (id)actionKey {
    return @{ @"guid": _guid };
}

- (BOOL)matchesActionKey:(id)actionKey {
    if ([actionKey isEqual:self.actionKey]) {
        return YES;
    }
    if ([actionKey isEqual:self.title]) {
        return YES;
    }
    return NO;
}

- (NSString *)displayTitle {
    if (self.title.length == 0) {
        return [self.value ellipsizedDescriptionNoLongerThan:30];
    }
    return self.title;
}

@end

@implementation iTermSnippetsModel {
    NSMutableArray<iTermSnippet *> *_snippets;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        __block NSInteger i = 0;
        _snippets = [[[NSArray castFrom:[[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeySnippets]] mapWithBlock:^id(id anObject) {
            NSDictionary *dict = [NSDictionary castFrom:anObject];
            if (!dict) {
                return nil;
            }
            return [[iTermSnippet alloc] initWithDictionary:dict index:i++];
        }] mutableCopy] ?: [NSMutableArray array];
    }
    return self;
}

- (void)addSnippet:(iTermSnippet *)snippet {
    [_snippets addObject:snippet];
    [self save];
    [[iTermSnippetsDidChangeNotification notificationWithMutationType:iTermSnippetsDidChangeMutationTypeInsertion index:_snippets.count - 1] post];
}

- (void)removeSnippets:(NSArray<iTermSnippet *> *)snippets {
    NSIndexSet *indexes = [_snippets it_indexSetWithIndexesOfObjects:snippets];
    [_snippets removeObjectsAtIndexes:indexes];
    [self save];
    [[iTermSnippetsDidChangeNotification removalNotificationWithIndexes:indexes] post];
}

- (void)replaceSnippet:(iTermSnippet *)snippetToReplace withSnippet:(iTermSnippet *)replacement {
    NSInteger index = [_snippets indexOfObject:snippetToReplace];
    if (index == NSNotFound) {
        return;
    }
    _snippets[index] = replacement;
    [self save];
    [[iTermSnippetsDidChangeNotification notificationWithMutationType:iTermSnippetsDidChangeMutationTypeEdit index:index] post];
}

- (NSInteger)indexOfSnippetWithGUID:(NSString *)guid {
    return [_snippets indexOfObjectPassingTest:^BOOL(iTermSnippet * _Nonnull snippet, NSUInteger idx, BOOL * _Nonnull stop) {
        return [snippet.guid isEqual:guid];
    }];
}

- (iTermSnippet *)snippetWithGUID:(NSString *)guid {
    const NSInteger i = [self indexOfSnippetWithGUID:guid];
    if (i == NSNotFound) {
        return nil;
    }
    return _snippets[i];
}

- (nullable iTermSnippet *)snippetWithActionKey:(id)actionKey {
    return [_snippets objectPassingTest:^BOOL(iTermSnippet *snippet, NSUInteger index, BOOL *stop) {
        return [snippet matchesActionKey:actionKey];
    }];
}

- (void)moveSnippetsWithGUIDs:(NSArray<NSString *> *)guids
                      toIndex:(NSInteger)row {
    NSArray<iTermSnippet *> *snippets = [_snippets filteredArrayUsingBlock:^BOOL(iTermSnippet *snippet) {
        return [guids containsObject:snippet.guid];
    }];
    NSInteger countBeforeRow = [[snippets filteredArrayUsingBlock:^BOOL(iTermSnippet *snippet) {
        return [self indexOfSnippetWithGUID:snippet.guid] < row;
    }] count];
    NSMutableArray<iTermSnippet *> *updatedSnippets = [_snippets mutableCopy];
    NSMutableIndexSet *removals = [NSMutableIndexSet indexSet];
    for (iTermSnippet *snippet in snippets) {
        const NSInteger i = [_snippets indexOfObject:snippet];
        assert(i != NSNotFound);
        [removals addIndex:i];
        [updatedSnippets removeObject:snippet];
    }
    NSInteger insertionIndex = row - countBeforeRow;
    for (iTermSnippet *snippet in snippets) {
        [updatedSnippets insertObject:snippet atIndex:insertionIndex++];
    }
    _snippets = updatedSnippets;
    [self save];
    [[iTermSnippetsDidChangeNotification moveNotificationWithRemovals:removals
                                                     destinationIndex:row - countBeforeRow] post];
}

- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets {
    _snippets = [snippets mutableCopy];
    [self save];
    [[iTermSnippetsDidChangeNotification fullReplacementNotification] post];
}

#pragma mark - Private

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:[self arrayOfDictionaries]
                                              forKey:kPreferenceKeySnippets];
}

- (NSArray<NSDictionary *> *)arrayOfDictionaries {
    return [_snippets mapWithBlock:^id(iTermSnippet *snippet) {
        return snippet.dictionaryValue;
    }];
}

@end

@implementation iTermSnippetsDidChangeNotification

+ (instancetype)notificationWithMutationType:(iTermSnippetsDidChangeMutationType)mutationType index:(NSInteger)index {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = mutationType;
    notif->_index = index;
    return notif;
}

+ (instancetype)moveNotificationWithRemovals:(NSIndexSet *)removals
                            destinationIndex:(NSInteger)destinationIndex {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeMove;
    notif->_indexSet = removals;
    notif->_index = destinationIndex;
    return notif;
}

+ (instancetype)fullReplacementNotification {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeFullReplacement;
    return notif;
}

+ (instancetype)removalNotificationWithIndexes:(NSIndexSet *)indexes {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeDeletion;
    notif->_indexSet = indexes;
    return notif;
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermSnippetsDidChangeNotification * _Nonnull notification))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
