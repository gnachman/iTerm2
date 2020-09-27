//
//  iTermActionsModel.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import "iTermActionsModel.h"
#import "iTermNotificationCenter+Protected.h"
#import "iTermPreferences.h"
#import "iTermSettingsProvider.h"
#import "NSArray+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSObject+iTerm.h"
#import "ProfileModel.h"

@implementation iTermAction

- (instancetype)initWithTitle:(NSString *)title
                       action:(KEY_ACTION)action
                    parameter:(NSString *)parameter {
    self = [super init];
    if (self) {
        _action = action;
        _title = [title copy];
        _parameter = [parameter copy];
        static NSInteger nextIdentifier;
        _identifier = nextIdentifier++;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    return [self initWithTitle:dictionary[@"title"] ?: @""
                        action:[dictionary[@"action"] intValue]
                     parameter:dictionary[@"parameter"] ?: @""];
}

- (NSDictionary *)dictionaryValue {
    return @{ @"action": @(_action),
              @"title": _title ?: @"",
              @"parameter": _parameter ?: @"" };
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    iTermAction *other = [iTermAction castFrom:object];
    if (!other) {
        return NO;
    }
    return [self.dictionaryValue isEqual:other.dictionaryValue];
}

- (NSString *)displayString {
    return [[iTermKeyBindingAction withAction:_action parameter:_parameter ?: @""] displayName];
}

@end

@implementation iTermActionsModel {
    NSMutableArray<iTermAction *> *_actions;
    id<iTermSettingsProvider> _settingsProvider;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithSettingsProvider:[iTermSettingsProviderGlobal sharedInstance]];
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
    iTermActionsModel *model = [map objectForKey:guid];
    if (!model) {
        id<iTermSettingsProvider> provider =
        [[iTermSettingsProviderProfile alloc] initWithGUID:guid
                                              profileModel:[ProfileModel sharedInstance]];
        model = [[iTermActionsModel alloc] initWithSettingsProvider:provider];
        [map setObject:model forKey:guid];
    }
    return model;
}

- (instancetype)initWithSettingsProvider:(id<iTermSettingsProvider>)settingsProvider {
    self = [super init];
    if (self) {
        _settingsProvider = settingsProvider;
        _actions = [[[NSArray castFrom:[_settingsProvider objectForKey:kPreferenceKeyActions]] mapWithBlock:^id(id anObject) {
            NSDictionary *dict = [NSDictionary castFrom:anObject];
            if (!dict) {
                return nil;
            }
            return [[iTermAction alloc] initWithDictionary:dict];
        }] mutableCopy] ?: [NSMutableArray array];
    }
    return self;
}

- (void)addAction:(iTermAction *)action {
    [_actions addObject:action];
    [self save];
    [[iTermActionsDidChangeNotification notificationWithMutationType:iTermActionsDidChangeMutationTypeInsertion
                                                               index:_actions.count - 1
                                                               model:self] post];
}

- (void)removeActions:(NSArray<iTermAction *> *)actions {
    NSIndexSet *indexes = [_actions it_indexSetWithIndexesOfObjects:actions];
    [_actions removeObjectsAtIndexes:indexes];
    [self save];
    [[iTermActionsDidChangeNotification removalNotificationWithIndexes:indexes
                                                                 model:self] post];
}

- (void)replaceAction:(iTermAction *)actionToReplace withAction:(iTermAction *)replacement {
    NSInteger index = [_actions indexOfObject:actionToReplace];
    if (index == NSNotFound) {
        return;
    }
    _actions[index] = replacement;
    [self save];
    [[iTermActionsDidChangeNotification notificationWithMutationType:iTermActionsDidChangeMutationTypeEdit
                                                               index:index
                                                               model:self] post];
}

- (NSInteger)indexOfActionWithIdentifier:(NSInteger)identifier {
    return [_actions indexOfObjectPassingTest:^BOOL(iTermAction * _Nonnull action, NSUInteger idx, BOOL * _Nonnull stop) {
        return action.identifier == identifier;
    }];
}

- (iTermAction *)actionWithIdentifier:(NSInteger)identifier {
    const NSInteger i = [self indexOfActionWithIdentifier:identifier];
    if (i == NSNotFound) {
        return nil;
    }
    return _actions[i];
}

- (void)moveActionsWithIdentifiers:(NSArray<NSNumber *> *)identifiers
                           toIndex:(NSInteger)row {
    NSArray<iTermAction *> *actions = [_actions filteredArrayUsingBlock:^BOOL(iTermAction *action) {
        return [identifiers containsObject:@(action.identifier)];
    }];
    NSInteger countBeforeRow = [[actions filteredArrayUsingBlock:^BOOL(iTermAction *action) {
        return [self indexOfActionWithIdentifier:action.identifier] < row;
    }] count];
    NSMutableArray<iTermAction *> *updatedActions = [_actions mutableCopy];
    NSMutableIndexSet *removals = [NSMutableIndexSet indexSet];
    for (iTermAction *action in actions) {
        const NSInteger i = [_actions indexOfObject:action];
        assert(i != NSNotFound);
        [removals addIndex:i];
        [updatedActions removeObject:action];
    }
    NSInteger insertionIndex = row - countBeforeRow;
    for (iTermAction *action in actions) {
        [updatedActions insertObject:action atIndex:insertionIndex++];
    }
    _actions = updatedActions;
    [self save];
    [[iTermActionsDidChangeNotification moveNotificationWithRemovals:removals
                                                    destinationIndex:row - countBeforeRow
                                                               model:self] post];
}

- (void)setActions:(NSArray<iTermAction *> *)actions {
    _actions = [actions mutableCopy];
    [self save];
    [[iTermActionsDidChangeNotification fullReplacementNotificationForModel:self] post];
}

#pragma mark - Private

- (void)save {
    [_settingsProvider setObject:[self arrayOfDictionaries]
                          forKey:kPreferenceKeyActions];
}

- (NSArray<NSDictionary *> *)arrayOfDictionaries {
    return [_actions mapWithBlock:^id(iTermAction *action) {
        return action.dictionaryValue;
    }];
}

@end

@implementation iTermActionsDidChangeNotification

+ (instancetype)notificationWithMutationType:(iTermActionsDidChangeMutationType)mutationType
                                       index:(NSInteger)index
                                       model:(nonnull iTermActionsModel *)model {
    iTermActionsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = mutationType;
    notif->_index = index;
    notif->_model = model;
    return notif;
}

+ (instancetype)moveNotificationWithRemovals:(NSIndexSet *)removals
                            destinationIndex:(NSInteger)destinationIndex
                                       model:(nonnull iTermActionsModel *)model {
    iTermActionsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermActionsDidChangeMutationTypeMove;
    notif->_indexSet = removals;
    notif->_index = destinationIndex;
    notif->_model = model;
    return notif;
}

+ (instancetype)fullReplacementNotificationForModel:(iTermActionsModel *)model {
    iTermActionsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermActionsDidChangeMutationTypeFullReplacement;
    notif->_model = model;
    return notif;
}

+ (instancetype)removalNotificationWithIndexes:(NSIndexSet *)indexes
                                         model:(nonnull iTermActionsModel *)model {
    iTermActionsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermActionsDidChangeMutationTypeDeletion;
    notif->_indexSet = indexes;
    notif->_model = model;
    return notif;
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermActionsDidChangeNotification * _Nonnull notification))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
