#import <Foundation/Foundation.h>

@class ProfileModel;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermBackgroundImageRotationDidChangeNotification;

@interface iTermBackgroundImageRotationManager : NSObject

+ (instancetype)sharedInstance;

- (nullable NSString *)backgroundImagePathForProfile:(NSDictionary *)profile;
- (void)profileDidChange:(NSDictionary *)profile;

@end

NS_ASSUME_NONNULL_END
