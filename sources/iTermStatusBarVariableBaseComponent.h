//
//  iTermStatusBarVariableBaseComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarTextComponent.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarVariableBaseComponent : iTermStatusBarTextComponent

@property (nonatomic, readonly) NSString *fullString;  // evaluates
@property (nonatomic, readonly) NSString *cached;  // cached fullString

- (instancetype)initWithPath:(NSString *)path
               configuration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_UNAVAILABLE;

// If you override stringVariants you don't need to provide this.
- (NSString *)stringByCompressingString:(NSString *)source;

@end

@interface iTermStatusBarHostnameComponent : iTermStatusBarVariableBaseComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPath:(NSString *)path
               configuration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_UNAVAILABLE;
@end

@interface iTermStatusBarUsernameComponent : iTermStatusBarVariableBaseComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPath:(NSString *)path
               configuration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_UNAVAILABLE;

@end

@interface iTermStatusBarWorkingDirectoryComponent : iTermStatusBarVariableBaseComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPath:(NSString *)path
               configuration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
