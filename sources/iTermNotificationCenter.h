//
//  iTermNotificationCenter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/1/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermBaseNotification<T> : NSObject<NSSecureCoding>
- (nullable instancetype)init NS_UNAVAILABLE;
- (void)post;
@end

@interface iTermPreferenceDidChangeNotification : iTermBaseNotification

@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly, nullable) id value;

+ (instancetype)notificationWithKey:(NSString *)key
                              value:(id)value;

+ (void)subscribe:(NSObject *)owner
            block:(void (^)(iTermPreferenceDidChangeNotification * _Nonnull notification))block;

@end

NS_ASSUME_NONNULL_END
