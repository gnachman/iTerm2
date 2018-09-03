//
//  iTermLocalHostNameGuesser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import "iTermLocalHostNameGuesser.h"

#import "DebugLogging.h"

typedef void (^iTermLocalHostReadyBlock)(NSString *);

@interface iTermLocalHostNameGuesser()
@property (atomic, copy, readwrite, nullable) NSString *name;
@end

@implementation iTermLocalHostNameGuesser {
    NSMutableArray<iTermLocalHostReadyBlock> *_blocks;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _blocks = [NSMutableArray array];
        [self guess];
    }
    return self;
}

- (void)callBlockWhenReady:(void (^)(NSString * _Nonnull))block {
    if (self.name) {
        block(self.name);
    } else {
        [_blocks addObject:[block copy]];
    }
}

- (void)guess {
    NSPipe *pipe = [NSPipe pipe];
    if (!pipe) {
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/hostname";
    task.arguments = @[ @"-f" ];
    task.standardOutput = pipe;
    @try {
        [task launch];
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to launch “hostname -f”: %@", exception);
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [task waitUntilExit];
        DLog(@"hostname -f finished with status %d", task.terminationStatus);
        if (task.terminationStatus == 0) {
            NSPipe *pipe = task.standardOutput;
            NSFileHandle *fileHandle = pipe.fileHandleForReading;
            NSData *data = [fileHandle readDataToEndOfFile];
            NSString *name = [[NSString alloc] initWithData:data
                                                   encoding:NSUTF8StringEncoding];
            self.name = [[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
        } else {
            self.name = @"localhost";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didBecomeReady];
        });
    });
}

- (void)didBecomeReady {
    for (iTermLocalHostReadyBlock block in _blocks) {
        block(self.name);
    }
    [_blocks removeAllObjects];
}

@end
