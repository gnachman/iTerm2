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

- (instancetype)initWithPath:(nullable NSString *)path
               configuration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                       scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope;

// If you override stringVariants you don't need to provide this.
- (nullable NSString *)stringByCompressingString:(NSString *)source;
- (NSString *)transformedValue:(NSString *)value;

@end

@interface iTermStatusBarHostnameComponent : iTermStatusBarVariableBaseComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPath:(nullable NSString *)path
               configuration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                       scope:(iTermVariableScope *)scope NS_UNAVAILABLE;
@end

@interface iTermStatusBarUsernameComponent : iTermStatusBarVariableBaseComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPath:(nullable NSString *)path
               configuration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                       scope:(iTermVariableScope *)scope NS_UNAVAILABLE;

@end

@interface iTermStatusBarWorkingDirectoryComponent : iTermStatusBarVariableBaseComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPath:(nullable NSString *)path
               configuration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                       scope:(iTermVariableScope *)scope NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
