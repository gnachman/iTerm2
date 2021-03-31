//
//  iTermCommandRunnerPool.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/2/19.
//

#import "iTermCommandRunnerPool.h"

#import "DebugLogging.h"
#import "iTermBackgroundCommandRunner.h"
#import "iTermCommandRunner.h"
#import "NSArray+iTerm.h"

@implementation iTermCommandRunnerPool {
@protected
    NSMutableArray<id<iTermCommandRunner>> *_idle;
    NSMutableArray<id<iTermCommandRunner>> *_terminating;
    NSMutableArray<id<iTermCommandRunner>> *_busy;
}

- (instancetype)initWithCapacity:(int)capacity
                         command:(NSString *)command
                       arguments:(NSArray<NSString *> *)arguments
                workingDirectory:(NSString *)workingDirectory
                     environment:(NSDictionary<NSString *, NSString *> *)environment {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _command = [command copy];
        _arguments = [arguments copy];
        _workingDirectory = [workingDirectory copy];
        _environment = [environment copy];
        _idle = [NSMutableArray array];
        _terminating = [NSMutableArray array];
        _busy = [NSMutableArray array];
    }
    return self;
}

- (NSString *)stateDump {
    return [NSString stringWithFormat:@"Idle:\n%@\n\nTerminating:\n%@\n\nBusy:\n%@\n",
            [self dumpArray:_idle], [self dumpArray:_terminating], [self dumpArray:_busy]];
}

- (NSString *)dumpArray:(NSArray<id<iTermCommandRunner>> *)array {
    return [[array mapWithBlock:^id(id<iTermCommandRunner> runner) {
        return [runner description];
    }] componentsJoinedByString:@"\n"];
}

- (iTermCommandRunner *)requestCommandRunnerWithTerminationBlock:(void (^)(iTermCommandRunner * _Nonnull, int))block {
    return (iTermCommandRunner *)[self internalRequestCommandRunnerWithTerminationBlock:(id)block];
}

- (nullable id<iTermCommandRunner>)internalRequestCommandRunnerWithTerminationBlock:(void (^)(id<iTermCommandRunner>, int))block {
    DLog(@"Command runner requested\n%@", [self stateDump]);
    if (_busy.count == _capacity) {
        DLog(@"Cannot return one because all are busy\n%@.", [self stateDump]);
        return nil;
    }
    if (_idle.count == 0) {
        [self createNewCommandRunner];
    }
    if (_idle.count == 0) {
        DLog(@"Failed to create new command runner");
        return nil;
    }
    id<iTermCommandRunner> commandRunner = [_idle lastObject];

    [self initializeRunner:commandRunner completion:block];

    DLog(@"Returning %@\n%@", commandRunner, [self stateDump]);
    return commandRunner;
}

- (void)initializeRunner:(id<iTermCommandRunner>)commandRunner completion:(void (^)(id<iTermCommandRunner>, int))block {
    __weak __typeof(commandRunner) weakCommandRunner = commandRunner;
    __weak __typeof(self) weakSelf = self;
    commandRunner.completion = ^(int code) {
        DLog(@"Command runner %@ died with code %@", weakCommandRunner, @(code));
        [weakSelf commandRunnerDied:weakCommandRunner];
        if (block) {
            DLog(@"Invoking client termination block");
            block(weakCommandRunner, code);
        }
    };

    DLog(@"Move command runner %@ from idle to busy", commandRunner);
    [_busy addObject:commandRunner];
    [_idle removeLastObject];
}

- (void)terminateCommandRunner:(iTermCommandRunner *)commandRunner {
    DLog(@"Terminate %@", commandRunner);
    if (![_busy containsObject:commandRunner]) {
        DLog(@"NOT TERMINATING - NOT IN BUSY LIST");
        return;
    }
    [_terminating addObject:commandRunner];
    [_busy removeObject:commandRunner];
    [commandRunner terminate];
}

#pragma mark - Private

- (void)createNewCommandRunner {
    DLog(@"Creating a new command runner");
    iTermCommandRunner *commandRunner = [[iTermCommandRunner alloc] initWithCommand:_command
                                                                      withArguments:_arguments
                                                                               path:_workingDirectory];
    if (!commandRunner) {
        return;
    }
    commandRunner.environment = _environment;

    [_idle addObject:commandRunner];
}

- (void)commandRunnerDied:(id<iTermCommandRunner>)commandRunner {
    DLog(@"Removing all references to dead command runner %@", commandRunner);
    if (!commandRunner) {
        return;
    }
    [_busy removeObject:commandRunner];
    [_idle removeObject:commandRunner];
    [_terminating removeObject:commandRunner];
}

@end

@implementation iTermBackgroundCommandRunnerPool {
    NSMutableArray<iTermBackgroundCommandRunnerPromise *> *_waiting;
}

- (instancetype)initWithCapacity:(int)capacity {
    self = [super initWithCapacity:capacity
                           command:nil
                         arguments:nil
                  workingDirectory:nil
                       environment:nil];
    if (self) {
        _waiting = [NSMutableArray array];
    }
    return self;
}

- (nullable iTermBackgroundCommandRunner *)requestBackgroundCommandRunnerWithTerminationBlock:(void (^ _Nullable)(iTermBackgroundCommandRunner *, int))block {
    iTermBackgroundCommandRunner *runner = (iTermBackgroundCommandRunner *)[super requestCommandRunnerWithTerminationBlock:(id)block];
    if (runner) {
        return runner;
    }

    iTermBackgroundCommandRunnerPromise *promise = [[iTermBackgroundCommandRunnerPromise alloc] initWithCommand:nil shell:nil title:nil];
    DLog(@"Will return a promise %@.", promise);
    promise.terminationBlock = block;
    [_waiting addObject:promise];
    return promise;
}

- (void)createNewCommandRunner {
    DLog(@"Creating a new command runner");
    iTermBackgroundCommandRunner *commandRunner = [[iTermBackgroundCommandRunner alloc] init];
    if (!commandRunner) {
        return;
    }
    [_idle addObject:commandRunner];
}

- (void)commandRunnerDied:(id<iTermCommandRunner>)commandRunner {
    DLog(@"waiting.count=%@", @(_waiting.count));
    [super commandRunnerDied:commandRunner];
    if (!_waiting.count) {
        return;
    }
    iTermBackgroundCommandRunnerPromise *promise = [_waiting firstObject];
    DLog(@"Fulfill promise %@", promise);
    assert(promise);
    [_waiting removeObjectAtIndex:0];
    void (^terminationBlock)(iTermBackgroundCommandRunner *, int) = promise.terminationBlock;
    promise.terminationBlock = nil;
    [self initializeRunner:promise completion:terminationBlock];
    [promise fulfill];
}

@end
