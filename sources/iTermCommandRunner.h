//
//  iTermCommandRunner.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import <Foundation/Foundation.h>

@interface iTermCommandRunner : NSObject

@property (nonatomic, copy) NSString *command;
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic, copy) NSString *currentDirectoryPath;
@property (nonatomic, copy) void (^completion)(int);
@property (nonatomic, copy) void (^outputHandler)(NSData *);
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;

+ (void)unzipURL:(NSURL *)zipURL
   withArguments:(NSArray<NSString *> *)arguments
     destination:(NSString *)destination
      completion:(void (^)(BOOL))completion;

+ (void)zipURLs:(NSArray<NSURL *> *)URLs
      arguments:(NSArray<NSString *> *)arguments
       toZipURL:(NSURL *)zipURL
     relativeTo:(NSURL *)baseURL
     completion:(void (^)(BOOL))completion;

- (instancetype)initWithCommand:(NSString *)command
                  withArguments:(NSArray<NSString *> *)arguments
                           path:(NSString *)currentDirectoryPath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)run;
- (void)runWithTimeout:(NSTimeInterval)timeout;
- (void)write:(NSData *)data completion:(void (^)(size_t, int))completion;
- (void)terminate;

// You can configure a special git path in advanced prefs. Call this to update $PATH.
- (void)loadPathForGit;

@end

// Saves all data read into output.
@interface iTermBufferedCommandRunner : iTermCommandRunner
@property (nonatomic, readonly) NSData *output;
@property (nonatomic, strong) NSNumber *maximumOutputSize;
@property (nonatomic, readonly) BOOL truncated;
@end

