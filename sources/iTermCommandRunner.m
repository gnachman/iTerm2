//
//  iTermCommandRunner.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import "iTermCommandRunner.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"

@implementation iTermCommandRunner

+ (void)unzipURL:(NSURL *)zipURL
   withArguments:(NSArray<NSString *> *)arguments
     destination:(NSString *)destination
      completion:(void (^)(BOOL))completion {
    NSArray<NSString *> *fullArgs = [arguments arrayByAddingObject:zipURL.path];
    iTermCommandRunner *runner = [[self alloc] initWithCommand:@"/usr/bin/unzip"
                                                 withArguments:fullArgs
                                                          path:destination];
    runner.completion = ^(int status) {
        completion(status == 0);
    };
    [runner run];
}

+ (void)zipURLs:(NSArray<NSURL *> *)URLs
      arguments:(NSArray<NSString *> *)arguments
       toZipURL:(NSURL *)zipURL
     relativeTo:(NSURL *)baseURL
     completion:(void (^)(BOOL))completion {
    NSMutableArray<NSString *> *fullArgs = [arguments mutableCopy];
    [fullArgs addObject:zipURL.path];
    [fullArgs addObjectsFromArray:[URLs mapWithBlock:^id(NSURL *url) {
        return url.relativePath;
    }]];
    iTermCommandRunner *runner = [[self alloc] initWithCommand:@"/usr/bin/zip"
                                                 withArguments:fullArgs
                                                          path:baseURL.path];
    runner.completion = ^(int status) {
        completion(status == 0);
    };
    [runner run];
}

- (instancetype)initWithCommand:(NSString *)command
                  withArguments:(NSArray<NSString *> *)arguments
                           path:(NSString *)currentDirectoryPath {
    self = [super init];
    if (self) {
        self.command = command;
        self.arguments = arguments;
        self.currentDirectoryPath = currentDirectoryPath;
    }
    return self;
}

- (void)run {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self runSynchronously];
    });
}

- (void)runSynchronously {
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [[NSPipe alloc] init];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    task.launchPath = self.command;
    if (self.currentDirectoryPath) {
        task.currentDirectoryPath = self.currentDirectoryPath;
    }
    task.arguments = self.arguments;
    DLog(@"runCommand: Launching %@", task);
    @try {
        [task launch];
    } @catch (NSException *e) {
        if (self.completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.completion(-1);
            });
        }
        return;
    }

    NSFileHandle *readHandle = [pipe fileHandleForReading];
    DLog(@"runCommand: Reading");
    NSData *inData = [readHandle availableData];
    while (inData.length) {
        DLog(@"runCommand: Read %@", inData);
        if (self.outputHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.outputHandler(inData);
            });
        } else {
#if DEBUG
            NSLog(@"%@", [[NSString alloc] initWithData:inData encoding:NSUTF8StringEncoding]);
#else
            DLog(@"%@", [[NSString alloc] initWithData:inData encoding:NSUTF8StringEncoding]);
#endif
        }
        DLog(@"runCommand: Reading");
        inData = [readHandle availableData];
    }

    DLog(@"runCommand: Done reading. Wait");
    [task waitUntilExit];
    if (self.completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.completion(task.terminationStatus);
        });
    }
}

@end
