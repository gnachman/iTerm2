//
//  iTermCommandRunner.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import "iTermCommandRunner.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"

@interface iTermCommandRunner()
@property (atomic) BOOL running;
@end

@implementation iTermCommandRunner {
    NSTask *_task;
    NSPipe *_pipe;
}

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
        _task = [[NSTask alloc] init];
        _pipe = [[NSPipe alloc] init];

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

- (void)runWithTimeout:(NSTimeInterval)timeout {
    if (![self launchTask]) {
        return;
    }
    NSTask *task = _task;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self readAndWait:task];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.running) {
            [task terminate];
            self->_task = nil;
        }
    });
}

- (BOOL)launchTask {
    [_task setStandardOutput:_pipe];
    [_task setStandardError:_pipe];
    _task.launchPath = self.command;
    if (self.currentDirectoryPath) {
        _task.currentDirectoryPath = self.currentDirectoryPath;
    }
    _task.arguments = self.arguments;
    DLog(@"runCommand: Launching %@", _task);
    @try {
        [_task launch];
    } @catch (NSException *e) {
        if (self.completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.completion(-1);
            });
        }
        return NO;
    }
    self.running = YES;
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [task waitUntilExit];
        // This makes -availableData return immediately.
        pipe.fileHandleForReading.readabilityHandler = nil;
        dispatch_semaphore_signal(sema);
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
        DLog(@"runCommand: Read %@", inData);
        [self didReadData:inData];
        if (!self.outputHandler) {
            DLog(@"%@: %@", [task.arguments componentsJoinedByString:@" "],
                 [[NSString alloc] initWithData:inData encoding:NSUTF8StringEncoding]);
        }
        DLog(@"runCommand: Reading");
        @try {
            inData = [readHandle availableData];
        } @catch (NSException *e) {
            inData = nil;
        }
    }

    DLog(@"runCommand: Done reading. Wait");
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    self.running = NO;
    if (self.completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.completion(task.terminationStatus);
        });
    }
}

- (void)didReadData:(NSData *)inData {
    if (!self.outputHandler) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.outputHandler(inData);
    });
}

@end

@implementation iTermBufferedCommandRunner {
    NSMutableData *_output;
}

- (void)didReadData:(NSData *)inData {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_output) {
            self->_output = [NSMutableData data];
        }
        [self->_output appendData:inData];
    });
    [super didReadData:inData];
}

@end

