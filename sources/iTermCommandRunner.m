//
//  iTermCommandRunner.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import "iTermCommandRunner.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSMutableData+iTerm.h"

@interface iTermCommandRunner()
@property (atomic) BOOL running;
@property (atomic) BOOL terminateAfterLaunch;
@end

static NSString *const iTermCommandRunnerErrorDomain = @"com.iterm2.command-runner";

@implementation iTermCommandRunner {
    NSTask *_task;
    NSPipe *_pipe;
    NSPipe *_inputPipe;
    dispatch_queue_t _readingQueue;
    dispatch_queue_t _writingQueue;
    dispatch_queue_t _waitingQueue;
}

+ (void)unzipURL:(NSURL *)zipURL
   withArguments:(NSArray<NSString *> *)arguments
     destination:(NSString *)destination
   callbackQueue:(dispatch_queue_t)callbackQueue
      completion:(void (^)(NSError *))completion {
    DLog(@"zipURL=%@ arguments=%@ destination=%@", zipURL, arguments, destination);
    
    NSArray<NSString *> *fullArgs = [arguments arrayByAddingObject:zipURL.path];
    iTermCommandRunner *runner = [[self alloc] initWithCommand:@"/usr/bin/unzip"
                                                 withArguments:fullArgs
                                                          path:destination];
    NSMutableString *errorText = [NSMutableString string];
    runner.outputHandler = ^(NSData *data, void (^handled)(void)) {
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        DLog(@"output: %@", string);
        if (string) {
            [errorText appendString:string];
        } else {
            [errorText appendString:@"\n[non-UTF-8 output]\n"];
        }
        static NSInteger maxLength = 1024 * 1024;
        if (errorText.length > maxLength) {
            [errorText replaceCharactersInRange:NSMakeRange(0, errorText.length - maxLength)
                                     withString:@""];
        }
        handled();
    };
    runner.completion = ^(int status) {
        DLog(@"completed status=%@", @(status));
        if (!status) {
            completion(nil);
            return;
        }
        completion([NSError errorWithDomain:iTermCommandRunnerErrorDomain
                                       code:1
                                   userInfo:@{ NSLocalizedDescriptionKey: errorText }]);
    };
    [runner run];
}

+ (void)zipURLs:(NSArray<NSURL *> *)URLs
      arguments:(NSArray<NSString *> *)arguments
       toZipURL:(NSURL *)zipURL
     relativeTo:(NSURL *)baseURL
  callbackQueue:(dispatch_queue_t)callbackQueue
     completion:(void (^)(BOOL))completion {
    NSMutableArray<NSString *> *fullArgs = [arguments mutableCopy];
    [fullArgs addObject:zipURL.path];
    [fullArgs addObjectsFromArray:[URLs mapWithBlock:^id(NSURL *url) {
        return url.relativePath;
    }]];
    iTermCommandRunner *runner = [[self alloc] initWithCommand:@"/usr/bin/zip"
                                                 withArguments:fullArgs
                                                          path:baseURL.path];
    if (callbackQueue) {
        runner.callbackQueue = callbackQueue;
    }
    runner.completion = ^(int status) {
        completion(status == 0);
    };
    runner.outputHandler = ^(NSData *data, void (^completion)(void)) {
        DLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        completion();
    };
    DLog(@"Running %@ %@", runner.command, [runner.arguments componentsJoinedByString:@" "]);
    [runner run];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _task = [[NSTask alloc] init];
        _pipe = [[NSPipe alloc] init];
        _inputPipe = [[NSPipe alloc] init];
        _readingQueue = dispatch_queue_create("com.iterm2.crun-reading", DISPATCH_QUEUE_SERIAL);
        _writingQueue = dispatch_queue_create("com.iterm2.crun-writing", DISPATCH_QUEUE_SERIAL);
        _waitingQueue = dispatch_queue_create("com.iterm2.crun-waiting", DISPATCH_QUEUE_SERIAL);
        _callbackQueue = dispatch_get_main_queue();
    }
    return self;
}

- (instancetype)initWithCommand:(NSString *)command
                  withArguments:(NSArray<NSString *> *)arguments
                           path:(NSString *)currentDirectoryPath {
    self = [self init];
    if (self) {
        self.command = command;
        self.arguments = arguments;
        self.currentDirectoryPath = currentDirectoryPath;
        _callbackQueue = dispatch_get_main_queue();
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p pid=%@>", self.class, self, @(_task.processIdentifier)];
}

- (void)run {
    dispatch_async(_readingQueue, ^{
        [self runSynchronously];
    });
}

- (void)runWithTimeout:(NSTimeInterval)timeout {
    if (![self launchTask]) {
        return;
    }
    NSTask *task = _task;
    dispatch_async(_readingQueue, ^{
        [self readAndWait:task];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), _callbackQueue, ^{
        if (self.running) {
            [task terminate];
            self->_task = nil;
        }
    });
}

- (void)terminate {
    @try {
        self.terminateAfterLaunch = YES;
        int pid = _task.processIdentifier;
        if (pid) {
            int rc = kill(pid, SIGKILL);
            DLog(@"kill -%@ %@ returned %@", @(SIGKILL), @(_task.processIdentifier), @(rc));
        } else {
            DLog(@"command runner %@ process ID is 0. Should terminate after launch.", self);
        }
    } @catch (NSException *exception) {
        DLog(@"terminate threw %@", exception);
    }
}

- (BOOL)launchTask {
    if (_environment) {
        _task.environment = _environment;
    }
    [_task setStandardInput:_inputPipe];
    [_task setStandardOutput:_pipe];
    [_task setStandardError:_pipe];
    _task.launchPath = self.command;
    if (self.currentDirectoryPath) {
        _task.currentDirectoryPath = self.currentDirectoryPath;
    }
    _task.arguments = self.arguments;
    DLog(@"runCommand: Launching %@", _task);
    @try {
        DLog(@"In %@ run: %@ %@", _task.currentDirectoryURL.path, _task.launchPath, _task.arguments);
        [_task launch];
        DLog(@"Launched %@", self);
    } @catch (NSException *e) {
        NSLog(@"Task failed with %@. launchPath=%@, pwd=%@, args=%@", e, _task.launchPath, _task.currentDirectoryPath, _task.arguments);
        DLog(@"Task failed with %@. launchPath=%@, pwd=%@, args=%@", e, _task.launchPath, _task.currentDirectoryPath, _task.arguments);
        if (self.completion) {
            dispatch_async(_callbackQueue, ^{
                self.completion(-1);
            });
        }
        return NO;
    }
    self.running = YES;
    if (self.terminateAfterLaunch) {
        DLog(@"terminate after launch %@", self);
        [self terminate];
    }
    return YES;
}

- (void)runSynchronously {
    if (![self launchTask]) {
        return;
    }
    [self readAndWait:_task];
}

- (void)readAndWait:(NSTask *)task {
    NSPipe *pipe = _pipe;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    DLog(@"%@ readAndWait starting", task);
    dispatch_async(_waitingQueue, ^{
        DLog(@"%@ readAndWait calling waitUntilExit", task);

        DLog(@"Wait for %@", task.executableURL.path);
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        task.terminationHandler = ^(NSTask *task) {
            DLog(@"Termination handler run for %@", task.executableURL.path);
            dispatch_group_leave(group);
        };
        dispatch_wait(group, DISPATCH_TIME_FOREVER);
        DLog(@"Resuming after termination of %@", task.executableURL.path);

        DLog(@"%@ readAndWait waitUntilExit returned", task);
        // This makes -availableData return immediately.
        pipe.fileHandleForReading.readabilityHandler = nil;
        DLog(@"%@ readAndWait signal sema", task);
        dispatch_semaphore_signal(sema);
        DLog(@"%@ readAndWait done signaling sema", task);
    });
    NSFileHandle *readHandle = [_pipe fileHandleForReading];
    DLog(@"runCommand: Reading");
    NSData *inData = nil;

    @try {
        inData = [readHandle availableData];
    } @catch (NSException *e) {
        inData = nil;
    }

    while (inData.length) {
        @autoreleasepool {
            DLog(@"runCommand: Read %@", inData);
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_enter(group);
            [self didReadData:inData completion:^{
                dispatch_group_leave(group);
            }];
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
            if (!self.outputHandler) {
                DLog(@"%@: %@", [task.arguments componentsJoinedByString:@" "],
                     [[NSString alloc] initWithData:inData encoding:NSUTF8StringEncoding]);
            }
            DLog(@"runCommand: Reading");
        }
        @try {
            inData = [readHandle availableData];
        } @catch (NSException *e) {
            inData = nil;
        }
    }

    DLog(@"runCommand: Done reading. Wait");
    DLog(@"%@ readAndWait wait on sema", task);
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    DLog(@"%@ readAndWait done waiting on sema", task);
    // When it times out the caller will terminate the task.

    self.running = NO;
    if (self.completion) {
        dispatch_async(_callbackQueue, ^{
            self.completion(task.terminationStatus);
        });
    }
}

- (void)write:(NSData *)data completion:(void (^)(size_t, int))completion {
    int fd = [[_inputPipe fileHandleForWriting] fileDescriptor];
    DLog(@"Planning to write %@ bytes to %@", @(data.length), self);

    dispatch_data_t dispatchData = dispatch_data_create(data.bytes, data.length, _writingQueue, ^{
        [data length];  // just ensure data is retained
    });
    dispatch_queue_t callbackQueue = _callbackQueue;
    dispatch_write(fd, dispatchData, _writingQueue, ^(dispatch_data_t  _Nullable data, int error) {
        if (completion) {
            dispatch_async(callbackQueue, ^{
                completion(data ? dispatch_data_get_size(data) : 0, error);
            });
        }
    });
}

- (void)didReadData:(NSData *)inData completion:(void (^)(void))completion {
    if (!self.outputHandler) {
        completion();
        return;
    }
    dispatch_async(_callbackQueue, ^{
        self.outputHandler(inData, completion);
    });
}

@end

@implementation iTermBufferedCommandRunner {
    NSMutableData *_output;
}

static NSMutableArray<iTermBufferedCommandRunner *> *gCommandRunners;

+ (void)runCommandWithPath:(NSString *)path
                 arguments:(NSArray<NSString *> *)arguments
                    window:(NSWindow *)window {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gCommandRunners = [NSMutableArray array];
    });
    iTermBufferedCommandRunner *runner =
    [[iTermBufferedCommandRunner alloc] initWithCommand:path
                                          withArguments:arguments
                                                   path:[[NSFileManager defaultManager] currentDirectoryPath]];
    DLog(@"Launch %@ %@ in runner %@", path, arguments, runner);
    runner.maximumOutputSize = @(1024 * 10);
    __weak __typeof(runner) weakRunner = runner;
    __weak __typeof(self) weakSelf = self;
    runner.completion = ^(int status) {
        __strong __typeof(runner) strongRunner = weakRunner;
        DLog(@"Command finished");
        if (strongRunner) {
            [gCommandRunners removeObject:strongRunner];
            [iTermBufferedCommandRunner runnerDidFinish:strongRunner withStatus:status];
        }
    };
    [gCommandRunners addObject:runner];
    [runner run];
}

+ (void)runnerDidFinish:(iTermBufferedCommandRunner *)runner withStatus:(int)status {
    [gCommandRunners removeObject:runner];
    DLog(@"Runner %@ finished with status %@. There are now %@ runners.", runner, @(status), @(gCommandRunners.count));
    if (!status) {
        return;
    }
    iTermWarning *warning = [[iTermWarning alloc] init];
    warning.title = [NSString stringWithFormat:@"The following command returned a non-zero exit code:\n\n“%@ %@”",
                     runner.command,
                     [runner.arguments componentsJoinedByString:@" "]];
    warning.heading = @"Command Failed";
    static const iTermSingleUseWindowOptions options = iTermSingleUseWindowOptionsShortLived;
    NSMutableData *inject = [runner.output mutableCopy];
    NSString *truncationWarning = [NSString stringWithFormat:@"\n%c[m;[output truncated]\n", 27];
    if (runner.truncated) {
        [inject appendData:[truncationWarning dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [inject it_replaceOccurrencesOfData:[NSData dataWithBytes:"\n" length:1]
                               withData:[NSData dataWithBytes:"\r\n" length:2]];
    warning.warningActions = @[ [iTermWarningAction warningActionWithLabel:@"OK" block:nil],
                                [iTermWarningAction warningActionWithLabel:@"View" block:^(iTermWarningSelection selection) {
                                    [[iTermController sharedInstance] openSingleUseWindowWithCommand:@"/usr/bin/true"
                                                                                           arguments:nil
                                                                                              inject:inject
                                                                                         environment:nil
                                                                                                 pwd:@"/"
                                                                                             options:options
                                                                                      didMakeSession:nil
                                                                                          completion:nil];
                                }] ];
    warning.warningType = kiTermWarningTypePermanentlySilenceable;
    NSString *name;
    if ([runner.command isEqualToString:@"/bin/sh"] &&
        [runner.arguments.firstObject isEqualToString:@"-c"] &&
        runner.arguments.count > 1) {
        name = runner.arguments[1];
    } else {
        name = runner.command;
    }
    warning.identifier = [@"NoSyncCommandFailed_" stringByAppendingString:name];
    [warning runModal];
}

- (void)didReadData:(NSData *)inData completion:(void (^)(void))completion {
    dispatch_async(self.callbackQueue, ^{
        [self saveData:inData];
        if (!self.outputHandler) {
            completion();
            return;
        }
        self.outputHandler(inData, completion);
    });
}

- (void)saveData:(NSData *)inData {
    if (!_output) {
        _output = [NSMutableData data];
    }
    if (_truncated) {
        return;
    }
    [_output appendData:inData];
    if (_maximumOutputSize && _output.length > _maximumOutputSize.unsignedIntegerValue) {
        _output.length = _maximumOutputSize.unsignedIntegerValue;
        _truncated = YES;
    }
}

@end

