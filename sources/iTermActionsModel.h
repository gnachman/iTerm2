//
//  iTermActionsModel.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import <Foundation/Foundation.h>

#import "iTermKeyBindingAction.h"
#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermAction : NSObject
@property (nonatomic, readonly) NSDictionary *dictionaryValue;
@property (nonatomic, readonly) KEY_ACTION action;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSString *parameter;
@property (nonatomic, readonly) NSInteger identifier;
@property (nonatomic, readonly) NSString *displayString;
@property (nonatomic, readonly) iTermSendTextEscaping escaping;
@property (nonatomic, readonly) iTermActionApplyMode applyMode;
@property (nonatomic, readonly) int version;

+ (int)currentVersion;

- (instancetype)initWithTitle:(NSString *)title
                       action:(KEY_ACTION)action
                    parameter:(NSString *)parameter
                     escaping:(iTermSendTextEscaping)escaping
                    applyMode:(iTermActionApplyMode)applyMode
                      version:(int)version NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

- (instancetype)init NS_UNAVAILABLE;
@end

@interface iTermActionsModel : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, readonly) NSArray<iTermAction *> *actions;

- (void)addAction:(iTermAction *)action;
- (void)removeActions:(NSArray<iTermAction *> *)actions;
- (void)replaceAction:(iTermAction *)actionToReplace
           withAction:(iTermAction *)replacement;
- (void)moveActionsWithIdentifiers:(NSArray<NSNumber *> *)identifiersToMove
                           toIndex:(NSInteger)row;
- (void)setActions:(NSArray<iTermAction *> *)actions;
- (nullable iTermAction *)actionWithIdentifier:(NSInteger)identifier;

@end

@interface iTermActionsDidChangeNotification : iTermBaseNotification

typedef NS_ENUM(NSUInteger, iTermActionsDidChangeMutationType) {
    iTermActionsDidChangeMutationTypeInsertion,
    iTermActionsDidChangeMutationTypeDeletion,
    iTermActionsDidChangeMutationTypeEdit,
    iTermActionsDidChangeMutationTypeMove,
    iTermActionsDidChangeMutationTypeFullReplacement
};

@property (nonatomic, readonly) iTermActionsDidChangeMutationType mutationType;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) NSIndexSet *indexSet;  // for move only

+ (instancetype)notificationWithMutationType:(iTermActionsDidChangeMutationType)mutationType
                                       index:(NSInteger)index;
+ (instancetype)moveNotificationWithRemovals:(NSIndexSet *)removals
                            destinationIndex:(NSInteger)destinationIndex;
+ (instancetype)fullReplacementNotification;
+ (instancetype)removalNotificationWithIndexes:(NSIndexSet *)indexes;

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermActionsDidChangeNotification * _Nonnull notification))block;
@end

NS_ASSUME_NONNULL_END
