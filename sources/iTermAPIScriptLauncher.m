//
//  iTermAPIScriptLauncher.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import "iTermAPIScriptLauncher.h"

#import "DebugLogging.h"
#import "iTermWebSocketCookieJar.h"
#import "NSStringITerm.h"
#import "PTYTask.h"

@implementation iTermAPIScriptLauncher

+ (void)launchScript:(NSString *)filename {
    @try {
        [self tryLaunchScript:filename];
    }
    @catch (NSException *e) {
        [self didFailToLaunchScript:filename withException:e];
    }
}

// THROWS
+ (void)tryLaunchScript:(NSString *)filename {
    NSTask *task = [[NSTask alloc] init];
    NSString *shell = [PTYTask userShell];

    task.launchPath = shell;
    task.arguments = [self argumentsToRunScript:filename];
    task.environment = [self environmentFromEnvironment:task.environment shell:shell];

    NSPipe *pipe = [[NSPipe alloc] init];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    [task launch];   // This can throw

    [self waitForTask:task readFromPipe:pipe];
}

+ (NSDictionary *)environmentFromEnvironment:(NSDictionary *)initialEnvironment
                                       shell:(NSString *)shell {
    NSMutableDictionary *environment = [initialEnvironment ?: @{} mutableCopy];

    NSString *cookie = [[iTermWebSocketCookieJar sharedInstance] newCookie];
    if (cookie) {
        environment[@"ITERM2_COOKIE"] = cookie;
    } else {
        ELog(@"Failed to generate a cookie");
    }
    environment[@"HOME"] = NSHomeDirectory();
    environment[@"SHELL"] = shell;
    return environment;
}

+ (NSArray *)argumentsToRunScript:(NSString *)filename {
    NSString *wrapper = [[NSBundle mainBundle] pathForResource:@"it2_api_wrapper" ofType:@"sh"];
    NSString *virtualEnv = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"iterm2env"];
    NSString *command = [NSString stringWithFormat:@"%@ %@ %@",
                         [wrapper stringWithEscapedShellCharactersExceptTabAndNewline],
                         [virtualEnv stringWithEscapedShellCharactersExceptTabAndNewline],
                         [filename stringWithEscapedShellCharactersExceptTabAndNewline]];
    return @[ @"-c", command ];
}

+ (void)waitForTask:(NSTask *)task readFromPipe:(NSPipe *)pipe {
    static NSMutableArray<dispatch_queue_t> *queues;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queues = [NSMutableArray array];
    });
    dispatch_queue_t q = dispatch_queue_create("com.iterm2.script", NULL);
    [queues addObject:q];
    dispatch_async(q, ^{
        NSFileHandle *readHandle = [pipe fileHandleForReading];
        NSData *inData = [readHandle availableData];
        while (inData.length) {
            NSLog(@"%@", [[NSString alloc] initWithData:inData encoding:NSUTF8StringEncoding]);
            inData = [readHandle availableData];
        }

        [task waitUntilExit];
        [queues removeObject:q];
    });
}

+ (void)didFailToLaunchScript:(NSString *)filename withException:(NSException *)e {
    ELog(@"Expection occurred %@", e);
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Error running script";
    alert.informativeText = [NSString stringWithFormat:@"Script at \"%@\" failed.\n\n%@",
                             filename, e.reason];
    [alert runModal];
}

@end

