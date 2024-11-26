//
//  iTermCommandRunner.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermCommandRunner<NSObject>
@property (nonatomic, copy,  nullable) void (^completion)(int);
- (void)run;
@end

@interface iTermCommandRunner : NSObject<iTermCommandRunner>

@property (nonatomic, copy) NSString *command;
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic, copy) NSString *currentDirectoryPath;
@property (nonatomic, copy, nullable) void (^completion)(int);
// Call the completion block after you're completely done processing the input.
// This gives backpressure to the background process.
@property (nonatomic, copy, nullable) void (^outputHandler)(NSData * _Nullable, void (^)(void));
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, strong, nullable) dispatch_queue_t callbackQueue;

+ (void)unzipURL:(NSURL *)zipURL
   withArguments:(NSArray<NSString *> *)arguments
     destination:(NSString *)destination
   callbackQueue:(dispatch_queue_t)callbackQueue
      completion:(void (^)(NSError * _Nullable))completion;

+ (void)zipURLs:(NSArray<NSURL *> *)URLs
      arguments:(NSArray<NSString *> *)arguments
       toZipURL:(NSURL *)zipURL
     relativeTo:(NSURL *)baseURL
callbackQueue:(dispatch_queue_t)callbackQueue
     completion:(void (^)(BOOL))completion;

- (instancetype)initWithCommand:(NSString *)command
                  withArguments:(NSArray<NSString *> *)arguments
                           path:(NSString *)currentDirectoryPath;
- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)run;
- (void)runWithTimeout:(NSTimeInterval)timeout;
- (int)blockingRun;
- (void)write:(NSData *)data completion:(void (^ _Nullable)(size_t, int))completion;
- (void)terminate;

@end

@class NSWindow;

// Saves all data read into output.
@interface iTermBufferedCommandRunner : iTermCommandRunner
@property (nonatomic, readonly, nullable) NSData *output;
@property (nonatomic, strong, nullable) NSNumber *maximumOutputSize;
@property (nonatomic, readonly) BOOL truncated;

+ (void)runCommandWithPath:(NSString *)path
                 arguments:(NSArray<NSString *> *)arguments
                    window:(NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
