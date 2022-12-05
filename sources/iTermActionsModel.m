//
//  iTermActionsModel.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import "iTermActionsModel.h"
#import "iTermNotificationCenter+Protected.h"
#import "iTermPreferences.h"
#import "NSArray+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermAction {
    NSDictionary *_dictionary;
}

+ (int)currentVersion {
    return 2;
}

- (instancetype)initWithTitle:(NSString *)title
                       action:(KEY_ACTION)action
                    parameter:(NSString *)parameter
                     escaping:(iTermSendTextEscaping)escaping
                    applyMode:(iTermActionApplyMode)applyMode
                      version:(int)version {
    self = [super init];
    if (self) {
        _action = action;
        _title = [title copy];
        _parameter = [parameter copy];
        static NSInteger nextIdentifier;
        _identifier = nextIdentifier++;
        _escaping = escaping;
        _applyMode = applyMode;
        _version = version;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    iTermSendTextEscaping escaping;
    const int version = [dictionary[@"version"] intValue];
    if (version == 0) {
        escaping = iTermSendTextEscapingCompatibility;  // v0 migration path
    } else if (version == 1) {
        escaping = iTermSendTextEscapingCommon;  // v1 migration path
    } else {
        // v2+
        escaping = [dictionary[@"escaping"] unsignedIntegerValue];  // newest format
    }
    self = [self initWithTitle:dictionary[@"title"] ?: @""
                        action:[dictionary[@"action"] intValue]
                     parameter:dictionary[@"parameter"] ?: @""
                      escaping:escaping
                     applyMode:[dictionary[@"applyMode"] unsignedIntegerValue]
                       version:version];
    if (self) {
        _dictionary = [dictionary copy];
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    if (_dictionary) {
        return _dictionary;
    }
    return @{ @"action": @(_action),
              @"title": _title ?: @"",
              @"parameter": _parameter ?: @"",
              @"version": @(_version),
              @"escaping": @(_escaping),
              @"applyMode": @(_applyMode)
    };
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
    return [[iTermKeyBindingAction withAction:_action
                                    parameter:_parameter ?: @""
                                     escaping:_escaping
                                    applyMode:_applyMode] displayName];
}

@end

@implementation iTermActionsModel {
    NSMutableArray<iTermAction *> *_actions;
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
        _actions = [[[NSArray castFrom:[[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyActions]] mapWithBlock:^id(id anObject) {
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
    [[iTermActionsDidChangeNotification notificationWithMutationType:iTermActionsDidChangeMutationTypeInsertion index:_actions.count - 1] post];
}

- (void)removeActions:(NSArray<iTermAction *> *)actions {
    NSIndexSet *indexes = [_actions it_indexSetWithIndexesOfObjects:actions];
    [_actions removeObjectsAtIndexes:indexes];
    [self save];
    [[iTermActionsDidChangeNotification removalNotificationWithIndexes:indexes] post];
}

- (void)replaceAction:(iTermAction *)actionToReplace withAction:(iTermAction *)replacement {
    NSInteger index = [_actions indexOfObject:actionToReplace];
    if (index == NSNotFound) {
        return;
    }
    _actions[index] = replacement;
    [self save];
    [[iTermActionsDidChangeNotification notificationWithMutationType:iTermActionsDidChangeMutationTypeEdit index:index] post];
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
                                                    destinationIndex:row - countBeforeRow] post];
}

- (void)setActions:(NSArray<iTermAction *> *)actions {
    _actions = [actions mutableCopy];
    [self save];
    [[iTermActionsDidChangeNotification fullReplacementNotification] post];
}

#pragma mark - Private

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:[self arrayOfDictionaries]
                                              forKey:kPreferenceKeyActions];
}

- (NSArray<NSDictionary *> *)arrayOfDictionaries {
    return [_actions mapWithBlock:^id(iTermAction *action) {
        return action.dictionaryValue;
    }];
}

@end

@implementation iTermActionsDidChangeNotification

+ (instancetype)notificationWithMutationType:(iTermActionsDidChangeMutationType)mutationType index:(NSInteger)index {
    iTermActionsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = mutationType;
    notif->_index = index;
    return notif;
}

+ (instancetype)moveNotificationWithRemovals:(NSIndexSet *)removals
                            destinationIndex:(NSInteger)destinationIndex {
    iTermActionsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermActionsDidChangeMutationTypeMove;
    notif->_indexSet = removals;
    notif->_index = destinationIndex;
    return notif;
}

+ (instancetype)fullReplacementNotification {
    iTermActionsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermActionsDidChangeMutationTypeFullReplacement;
    return notif;
}

+ (instancetype)removalNotificationWithIndexes:(NSIndexSet *)indexes {
    iTermActionsDidChangeNotification *notif = [[self alloc] initPrivate];
    notif->_mutationType = iTermActionsDidChangeMutationTypeDeletion;
    notif->_indexSet = indexes;
    return notif;
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermActionsDidChangeNotification * _Nonnull notification))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
