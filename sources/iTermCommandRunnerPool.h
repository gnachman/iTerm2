//
//  iTermCommandRunnerPool.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/2/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermCommandRunner;

@interface iTermCommandRunnerPool : NSObject

@property (nonatomic, readonly) int capacity;
@property (nonatomic, readonly, copy) NSString *command;
@property (nonatomic, readonly, copy) NSArray<NSString *> *arguments;
@property (nonatomic, readonly, copy) NSString *workingDirectory;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;

- (instancetype)initWithCapacity:(int)capacity
                         command:(NSString *)command
                       arguments:(NSArray<NSString *> *)arguments
                workingDirectory:(NSString *)workingDirectory
                     environment:(NSDictionary<NSString *, NSString *> *)environment NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (nullable iTermCommandRunner *)requestCommandRunnerWithTerminationBlock:(void (^)(iTermCommandRunner *, int))block;
- (void)terminateCommandRunner:(iTermCommandRunner *)commandRunner;

@end

NS_ASSUME_NONNULL_END
