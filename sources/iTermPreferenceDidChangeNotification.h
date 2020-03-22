//
//  iTermPreferenceDidChangeNotification.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermNotificationCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermPreferenceDidChangeNotification : iTermBaseNotification

@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly, nullable) id value;

+ (instancetype)notificationWithKey:(NSString *)key
                              value:(nullable id)value;

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermPreferenceDidChangeNotification * _Nonnull notification))block;

@end

NS_ASSUME_NONNULL_END
