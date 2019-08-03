//
//  iTermCommandRunnerPool.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/2/19.
//

#import "iTermCommandRunnerPool.h"

#import "DebugLogging.h"
#import "iTermCommandRunner.h"
#import "NSArray+iTerm.h"

@implementation iTermCommandRunnerPool {
    NSMutableArray<iTermCommandRunner *> *_idle;
    NSMutableArray<iTermCommandRunner *> *_terminating;
    NSMutableArray<iTermCommandRunner *> *_busy;
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

- (NSString *)dumpArray:(NSArray<iTermCommandRunner *> *)array {
    return [[array mapWithBlock:^id(iTermCommandRunner *runner) {
        return [runner description];
    }] componentsJoinedByString:@"\n"];
}

- (nullable iTermCommandRunner *)requestCommandRunnerWithTerminationBlock:(void (^)(iTermCommandRunner *, int))block {
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
    iTermCommandRunner *commandRunner = [_idle lastObject];
    
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

    DLog(@"Returning %@\n%@", commandRunner, [self stateDump]);
    return commandRunner;
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

- (void)commandRunnerDied:(iTermCommandRunner *)commandRunner {
    DLog(@"Removing all references to dead command runner %@", commandRunner);
    if (!commandRunner) {
        return;
    }
    [_busy removeObject:commandRunner];
    [_idle removeObject:commandRunner];
    [_terminating removeObject:commandRunner];
}

@end
