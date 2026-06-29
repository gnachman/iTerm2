//
//  iTermCommandRunnerPool.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/2/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermBackgroundCommandRunner;
@class iTermCommandRunner;

@interface iTermCommandRunnerPool : NSObject

@property (nonatomic, readonly) int capacity;
@property (nullable, nonatomic, readonly, copy) NSString *command;
@property (nullable, nonatomic, readonly, copy) NSArray<NSString *> *arguments;
@property (nullable, nonatomic, readonly, copy) NSString *workingDirectory;
@property (nullable, nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;

- (instancetype)initWithCapacity:(int)capacity
                         command:(nullable NSString *)command
                       arguments:(nullable NSArray<NSString *> *)arguments
                workingDirectory:(nullable NSString *)workingDirectory
                     environment:(nullable NSDictionary<NSString *, NSString *> *)environment NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (nullable iTermCommandRunner *)requestCommandRunnerWithTerminationBlock:(void (^ _Nullable)(iTermCommandRunner *, int))block;
- (void)terminateCommandRunner:(iTermCommandRunner *)commandRunner;

@end

@interface iTermBackgroundCommandRunnerPool: iTermCommandRunnerPool

- (instancetype)initWithCapacity:(int)capacity NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCapacity:(int)capacity
                         command:(nullable NSString *)command
                       arguments:(nullable NSArray<NSString *> *)arguments
                workingDirectory:(nullable NSString *)workingDirectory
                     environment:(nullable NSDictionary<NSString *, NSString *> *)environment NS_UNAVAILABLE;

- (nullable iTermCommandRunner *)requestCommandRunnerWithTerminationBlock:(void (^ _Nullable)(iTermCommandRunner *, int))block NS_UNAVAILABLE;
- (nullable iTermBackgroundCommandRunner *)requestBackgroundCommandRunnerWithTerminationBlock:(void (^ _Nullable)(iTermBackgroundCommandRunner *, int))block;
@end

NS_ASSUME_NONNULL_END
