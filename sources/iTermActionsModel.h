//
//  iTermActionsModel.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/19.
//

#import <Foundation/Foundation.h>
#import "iTermKeyBindingMgr.h"
#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermAction : NSObject
@property (nonatomic, readonly) NSDictionary *dictionaryValue;

@property (nonatomic, readonly) KEY_ACTION action;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSString *parameter;

- (instancetype)initWithTitle:(NSString *)title
                       action:(KEY_ACTION)action
                    parameter:(NSString *)parameter NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

- (instancetype)init NS_UNAVAILABLE;
@end

@interface iTermActionsModel : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, readonly) NSArray<iTermAction *> *actions;

- (void)addAction:(iTermAction *)action;
- (void)removeAction:(iTermAction *)action;
- (void)replaceAction:(iTermAction *)actionToReplace
           withAction:(iTermAction *)replacement;

@end

@interface iTermActionsDidChangeNotification : iTermBaseNotification

typedef NS_ENUM(NSUInteger, iTermActionsDidChangeMutationType) {
    iTermActionsDidChangeMutationTypeInsertion,
    iTermActionsDidChangeMutationTypeDeletion,
    iTermActionsDidChangeMutationTypeEdit
};

@property (nonatomic, readonly) iTermActionsDidChangeMutationType mutationType;
@property (nonatomic, readonly) NSInteger index;

+ (instancetype)notificationWithMutationType:(iTermActionsDidChangeMutationType)mutationType
                                       index:(NSInteger)index;

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermActionsDidChangeNotification * _Nonnull notification))block;
@end

NS_ASSUME_NONNULL_END
