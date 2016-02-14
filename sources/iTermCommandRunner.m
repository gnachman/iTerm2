//
//  iTermCommandRunner.m
//  iTerm2
//
//  Created by George Nachman on 2/10/16.
//
//

#import "iTermCommandRunner.h"
#import "iTermWeakReference.h"

#import "DebugLogging.h"

@implementation iTermCommandRunner {
    NSString *_command;
    NSArray<NSString *> *_arguments;
    dispatch_queue_t _queue;
}

- (instancetype)initWithCommand:(NSString *)command
                      arguments:(NSArray<NSString *> *)arguments {
    self = [super init];
    if (self) {
        _command = [command copy];
        _arguments = [arguments copy];
        _queue = dispatch_queue_create("com.iterm2.CommandRunner", NULL);
    }
    return self;
}

- (void)dealloc {
    [_command release];
    [_arguments release];
    dispatch_release(_queue);
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %@ %@>",
            NSStringFromClass([self class]), self, _command, _arguments];
}

- (void)runWithCompletion:(void (^)(NSData * _Nullable, int))completion {
    NSPipe *pipe = [NSPipe pipe];
    if (!pipe) {
        completion(nil, 0);
    }
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = _command;
    task.arguments = _arguments;
    task.standardOutput = pipe;
    @try {
        [task launch];
    }
    @catch (NSException *exception) {
        ELog(@"Failed to run command: %@", self);
        completion(nil, 0);
        [task release];
        return;
    }
    [self retain];
    [completion retain];
    dispatch_async(_queue, ^{
        [task waitUntilExit];
        DLog(@"%@ finished with status %d", self, task.terminationStatus);
        NSPipe *pipe = task.standardOutput;
        NSFileHandle *fileHandle = pipe.fileHandleForReading;
        NSData *data = [fileHandle readDataToEndOfFile];
        completion(data, task.terminationStatus);
        [task release];
        [completion release];
        [self release];
    });

}

@end
