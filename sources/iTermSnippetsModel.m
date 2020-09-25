//
//  iTermSnippetsModel.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import "iTermSnippetsModel.h"
#import "iTermNotificationCenter+Protected.h"
#import "iTermPreferences.h"
#import "iTermSettingsProvider.h"
#import "NSArray+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "ProfileModel.h"

@implementation iTermSnippet

- (instancetype)initWithTitle:(NSString *)title
                        value:(NSString *)value {
    if (self) {
        _title = [title copy];
        _value = [value copy];
        static NSInteger nextIdentifier;
        _identifier = nextIdentifier++;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    return [self initWithTitle:dictionary[@"title"] ?: @""
                         value:dictionary[@"value"] ?: @""];
}

- (NSDictionary *)dictionaryValue {
    return @{ @"title": _title ?: @"",
              @"value": _value ?: @"" };
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    iTermSnippet *other = [iTermSnippet castFrom:object];
    if (!other) {
        return NO;
    }
    return self.identifier == other.identifier;
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

@end

@implementation iTermSnippetsModel {
    NSMutableArray<iTermSnippet *> *_snippets;
    id<iTermSettingsProvider> _settingsProvider;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermSnippetsModel alloc] initWithSettingsProvider:[iTermSettingsProviderGlobal sharedInstance]];
    });
    return instance;
}

+ (instancetype)instanceForProfileWithGUID:(NSString *)guid {
    static NSMapTable *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSPointerFunctionsOptions strong = (NSPointerFunctionsStrongMemory |
                                            NSPointerFunctionsObjectPersonality);
        NSPointerFunctionsOptions weak = (NSPointerFunctionsWeakMemory |
                                          NSPointerFunctionsObjectPersonality);
        map = [[NSMapTable alloc] initWithKeyOptions:strong
                                        valueOptions:weak
                                            capacity:1];
    });
    iTermSnippetsModel *model = [map objectForKey:guid];
    if (!model) {
        id<iTermSettingsProvider> provider =
        [[iTermSettingsProviderProfile alloc] initWithGUID:guid
                                              profileModel:[ProfileModel sharedInstance]];
        model = [[iTermSnippetsModel alloc] initWithSettingsProvider:provider];
        [map setObject:model forKey:guid];
    }
    return model;
}

- (instancetype)initWithSettingsProvider:(id<iTermSettingsProvider>)settingsProvider {
    self = [super init];
    if (self) {
        _settingsProvider = settingsProvider;
        _snippets = [[[NSArray castFrom:[_settingsProvider objectForKey:kPreferenceKeySnippets]] mapWithBlock:^id(id anObject) {
            NSDictionary *dict = [NSDictionary castFrom:anObject];
            if (!dict) {
                return nil;
            }
            return [[iTermSnippet alloc] initWithDictionary:dict];
        }] mutableCopy] ?: [NSMutableArray array];
    }
    return self;
}

- (void)addSnippet:(iTermSnippet *)snippet {
    [_snippets addObject:snippet];
    [self save];
    [[iTermSnippetsDidChangeNotification notificationWithMutationType:iTermSnippetsDidChangeMutationTypeInsertion
                                                                index:_snippets.count - 1
                                                                model:self] post];
}

- (void)removeSnippets:(NSArray<iTermSnippet *> *)snippets {
    NSIndexSet *indexes = [_snippets it_indexSetWithIndexesOfObjects:snippets];
    [_snippets removeObjectsAtIndexes:indexes];
    [self save];
    [[iTermSnippetsDidChangeNotification removalNotificationWithIndexes:indexes
                                                                  model:self] post];
}

- (void)replaceSnippet:(iTermSnippet *)snippetToReplace withSnippet:(iTermSnippet *)replacement {
    NSInteger index = [_snippets indexOfObject:snippetToReplace];
    if (index == NSNotFound) {
        return;
    }
    _snippets[index] = replacement;
    [self save];
    [[iTermSnippetsDidChangeNotification notificationWithMutationType:iTermSnippetsDidChangeMutationTypeEdit
                                                                index:index
                                                                model:self] post];
}

- (NSInteger)indexOfSnippetWithIdentifier:(NSInteger)identifier {
    return [_snippets indexOfObjectPassingTest:^BOOL(iTermSnippet * _Nonnull snippet, NSUInteger idx, BOOL * _Nonnull stop) {
        return snippet.identifier == identifier;
    }];
}

- (iTermSnippet *)snippetWithIdentifier:(NSInteger)identifier {
    const NSInteger i = [self indexOfSnippetWithIdentifier:identifier];
    if (i == NSNotFound) {
        return nil;
    }
    return _snippets[i];
}

- (void)moveSnippetsWithIdentifiers:(NSArray<NSNumber *> *)identifiers
                            toIndex:(NSInteger)row {
    NSArray<iTermSnippet *> *snippets = [_snippets filteredArrayUsingBlock:^BOOL(iTermSnippet *snippet) {
        return [identifiers containsObject:@(snippet.identifier)];
    }];
    NSInteger countBeforeRow = [[snippets filteredArrayUsingBlock:^BOOL(iTermSnippet *snippet) {
        return [self indexOfSnippetWithIdentifier:snippet.identifier] < row;
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
                                                     destinationIndex:row - countBeforeRow
                                                                model:self] post];
}

- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets {
    _snippets = [snippets mutableCopy];
    [self save];
    [[iTermSnippetsDidChangeNotification fullReplacementNotificationForModel:self] post];
}

#pragma mark - Private

- (void)save {
    [_settingsProvider setObject:[self arrayOfDictionaries]
                          forKey:kPreferenceKeySnippets];
}

- (NSArray<NSDictionary *> *)arrayOfDictionaries {
    return [_snippets mapWithBlock:^id(iTermSnippet *snippet) {
        return snippet.dictionaryValue;
    }];
}

@end

@implementation iTermSnippetsDidChangeNotification

+ (instancetype)notificationWithMutationType:(iTermSnippetsDidChangeMutationType)mutationType
                                       index:(NSInteger)index
                                       model:(nonnull iTermSnippetsModel *)model {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = mutationType;
    notif->_index = index;
    notif->_model = model;
    return notif;
}

+ (instancetype)moveNotificationWithRemovals:(NSIndexSet *)removals
                            destinationIndex:(NSInteger)destinationIndex
                                       model:(nonnull iTermSnippetsModel *)model {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeMove;
    notif->_indexSet = removals;
    notif->_index = destinationIndex;
    notif->_model = model;
    return notif;
}

+ (instancetype)fullReplacementNotificationForModel:(iTermSnippetsModel *)model {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeFullReplacement;
    notif->_model = model;
    return notif;
}

+ (instancetype)removalNotificationWithIndexes:(NSIndexSet *)indexes
                                         model:(nonnull iTermSnippetsModel *)model {
    iTermSnippetsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermSnippetsDidChangeMutationTypeDeletion;
    notif->_indexSet = indexes;
    notif->_model = model;
    return notif;
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermSnippetsDidChangeNotification * _Nonnull notification))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
