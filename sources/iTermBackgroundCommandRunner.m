//
//  iTermBackgroundCommandRunner.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/20/20.
//

#import "iTermBackgroundCommandRunner.h"

#import "DebugLogging.h"
#import "iTermCommandRunner.h"
#import "iTermNotificationController.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermScriptConsole.h"
#import "iTermScriptHistory.h"
#import "iTermSlowOperationGateway.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"

static NSString *const iTermBackgroundCommandRunnerDidSelectNotificationNotificationName = @"iTermBackgroundCommandRunnerDidSelectNotificationNotificationName";
static NSMutableArray<iTermBackgroundCommandRunner *> *activeRunners;

@interface iTermBackgroundCommandRunnerNotificationObserver: NSObject
+ (instancetype)sharedInstance;
@end

@implementation iTermBackgroundCommandRunnerNotificationObserver

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static iTermBackgroundCommandRunnerNotificationObserver *instance;
    dispatch_once(&onceToken, ^{
        instance = [[iTermBackgroundCommandRunnerNotificationObserver alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didSelectNotification:)
                                                     name:iTermBackgroundCommandRunnerDidSelectNotificationNotificationName
                                                   object:nil];
    }
    return self;
}

- (void)didSelectNotification:(NSNotification *)notification {
    NSString *identifier = notification.userInfo[@"identifier"];
    DLog(@"Did select notification with identifier %@", identifier);
    if (!identifier) {
        return;
    }
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] entryWithIdentifier:identifier];
    if (!entry) {
        return;
    }
    [[iTermScriptConsole sharedInstance] revealTailOfHistoryEntry:entry];
}

@end

@implementation iTermBackgroundCommandRunner {
    BOOL _running;
}

@synthesize completion;

+ (void)maybeNotify:(void (^)(NSInteger))block {
    static iTermRateLimitedUpdate *rateLimit;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rateLimit = [[iTermRateLimitedUpdate alloc] init];
        rateLimit.minimumInterval = 10;
    });
    [rateLimit performRateLimitedBlock:^{
        block(rateLimit.deferCount);
    }];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            activeRunners = [NSMutableArray array];
        });
    }
    return self;
}

- (instancetype)initWithCommand:(NSString *)command
                          shell:(NSString *)shell
                          title:(NSString *)title {
    self = [self init];
    if (self) {
        _command = command.copy;
        _shell = shell.copy;
        _title = title.copy;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p command=%@ shell=%@ title=%@ path=%@ running=%@>",
            NSStringFromClass(self.class), self, self.command, self.shell, self.title, self.path, @(_running)];
}

- (void)run {
    DLog(@"%@", self);
    if (self.path) {
        [self reallyRun];
        return;
    }
    DLog(@"Exfiltrate path");
    [[iTermSlowOperationGateway sharedInstance] exfiltrateEnvironmentVariableNamed:@"PATH"
                                                                             shell:self.shell
                                                                        completion:^(NSString * _Nonnull value) {
        self.path = value ?: @"";
        DLog(@"%@", self);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reallyRun];
        });
    }];
}

- (void)reallyRun {
    DLog(@"%@", self);
    assert(!_running);
    _running = YES;
    iTermCommandRunner *commandRunner = [[iTermCommandRunner alloc] initWithCommand:@"/bin/sh"
                                                                      withArguments:@[ @"-c", self.command ]
                                                                               path:[[NSFileManager defaultManager] currentDirectoryPath]];
    if (self.path.length > 0) {
        NSDictionary *environment = [[NSProcessInfo processInfo] environment];
        environment = [environment dictionaryBySettingObject:self.path forKey:@"PATH"];
        commandRunner.environment = environment;
    }
    iTermScriptHistoryEntry *entry =
    [[iTermScriptHistoryEntry alloc] initWithName:self.title
                                         fullPath:self.command
                                       identifier:[[NSUUID UUID] UUIDString]
                                         relaunch:nil];
    [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
    [entry addOutput:[NSString stringWithFormat:@"Run command:\n%@\n", self.command]
          completion:^{}];
    [activeRunners addObject:self];
    __weak __typeof(self) weakSelf = self;
    commandRunner.outputHandler = ^(NSData *data, void (^completion)(void)) {
        NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!string) {
            string = [data it_hexEncoded];
        }
        DLog(@"%@: add output %@", weakSelf, string);
        [entry addOutput:string completion:completion];
    };
    commandRunner.completion = ^(int status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf didCompleteWithStatus:status entry:entry];
        });
    };
    [commandRunner run];
}

- (void)didCompleteWithStatus:(int)status entry:(iTermScriptHistoryEntry *)entry {
    DLog(@"%@", self);
    [activeRunners removeObject:self];
    if (status) {
        [entry addOutput:[NSString stringWithFormat:@"\nFinished with status %d", status]
              completion:^{}];
    }
    [entry stopRunning];
    _running = NO;
    if (self.notificationTitle && status) {
        DLog(@"%@ post notification with identifier %@", self, entry.identifier);
        [iTermBackgroundCommandRunnerNotificationObserver sharedInstance];
        [self.class maybeNotify:^(NSInteger deferCount) {
            NSString *detail = [NSString stringWithFormat:@"\nFinished with status %d", status];
            if (deferCount > 1) {
                detail = [detail stringByAppendingFormat:@", plus %@ other error%@ silenced.",
                          @(deferCount - 1),
                          deferCount > 2 ? @"s" : @""];
            }
            [[iTermNotificationController sharedInstance] postNotificationWithTitle:self.notificationTitle
                                                                             detail:detail
                                                           callbackNotificationName:iTermBackgroundCommandRunnerDidSelectNotificationNotificationName
                                                       callbackNotificationUserInfo:@{ @"identifier": entry.identifier }];
        }];
    }
    if (self.completion) {
        self.completion(status);
    }
}

@end

@implementation iTermBackgroundCommandRunnerPromise {
    BOOL _fulfilled;
}

- (void)fulfill {
    if (_fulfilled) {
        return;
    }
    _fulfilled = YES;
    [self run];
}

- (void)run {
    if (!_fulfilled) {
        return;
    }
    [super run];
}
@end
