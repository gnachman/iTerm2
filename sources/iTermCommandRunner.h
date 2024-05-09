//
//  iTermCommandRunner.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import <Foundation/Foundation.h>

@protocol iTermCommandRunner<NSObject>
@property (nonatomic, copy) void (^completion)(int);
- (void)run;
@end

@interface iTermCommandRunner : NSObject<iTermCommandRunner>

@property (nonatomic, copy) NSString *command;
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic, copy) NSString *currentDirectoryPath;
@property (nonatomic, copy) void (^completion)(int);
// Call the completion block after you're completely done processing the input.
// This gives backpressure to the background process.
@property (nonatomic, copy) void (^outputHandler)(NSData *, void (^)(void));
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, strong) dispatch_queue_t callbackQueue;

+ (void)unzipURL:(NSURL *)zipURL
   withArguments:(NSArray<NSString *> *)arguments
     destination:(NSString *)destination
   callbackQueue:(dispatch_queue_t)callbackQueue
      completion:(void (^)(NSError *))completion;

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
- (void)write:(NSData *)data completion:(void (^)(size_t, int))completion;
- (void)terminate;

@end

@class NSWindow;

// Saves all data read into output.
@interface iTermBufferedCommandRunner : iTermCommandRunner
@property (nonatomic, readonly) NSData *output;
@property (nonatomic, strong) NSNumber *maximumOutputSize;
@property (nonatomic, readonly) BOOL truncated;

+ (void)runCommandWithPath:(NSString *)path
                 arguments:(NSArray<NSString *> *)arguments
                    window:(NSWindow *)window;

@end

