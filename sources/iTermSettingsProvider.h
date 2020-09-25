//
//  iTermSettingsProvider.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/20/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ProfileModel;

@protocol iTermSettingsProvider<NSObject>
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key;
@end

@interface iTermSettingsProviderProfile: NSObject<iTermSettingsProvider>
@property (nonatomic, readonly, copy) NSString *guid;
@property (nonatomic, readonly, strong) ProfileModel *profileModel;

- (instancetype)initWithGUID:(NSString *)guid
                profileModel:(ProfileModel *)profileModel NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface iTermSettingsProviderGlobal: NSObject<iTermSettingsProvider>
+ (instancetype)sharedInstance;
@end

NS_ASSUME_NONNULL_END
