//
//  iTermActionsModel.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import "iTermActionsModel.h"
#import "iTermNotificationCenter+Protected.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

static NSString *const iTermActionsUserDefaultsKey = @"Actions";

@implementation iTermAction

- (instancetype)initWithTitle:(NSString *)title
                       action:(KEY_ACTION)action
                    parameter:(NSString *)parameter {
    self = [super init];
    if (self) {
        _action = action;
        _title = [title copy];
        _parameter = [parameter copy];
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
        _actions = [[[NSArray castFrom:[[NSUserDefaults standardUserDefaults] objectForKey:iTermActionsUserDefaultsKey]] mapWithBlock:^id(id anObject) {
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

- (void)removeAction:(iTermAction *)action {
    NSInteger index = [_actions indexOfObject:action];
    if (index == NSNotFound) {
        return;
    }
    [_actions removeObject:action];
    [self save];
    [[iTermActionsDidChangeNotification notificationWithMutationType:iTermActionsDidChangeMutationTypeDeletion index:index] post];
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

#pragma mark - Private

- (void)save {
    [[NSUserDefaults standardUserDefaults] setObject:[self arrayOfDictionaries]
                                              forKey:iTermActionsUserDefaultsKey];
}

- (NSArray<NSDictionary *> *)arrayOfDictionaries {
    return [_actions mapWithBlock:^id(iTermAction *action) {
        return action.dictionaryValue;
    }];
}

@end

@implementation iTermActionsDidChangeNotification

+ (instancetype)notificationWithMutationType:(iTermActionsDidChangeMutationType)mutationType index:(NSInteger)index {
    iTermActionsDidChangeNotification *notif = [[self alloc] init];
    notif->_mutationType = mutationType;
    notif->_index = index;
    return notif;
}

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermActionsDidChangeNotification * _Nonnull notification))block {
    [self internalSubscribe:owner withBlock:block];
}

@end
