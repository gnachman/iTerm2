//
//  iTermOrphanServerAdopter.m
//  iTerm2
//
//  Created by George Nachman on 6/7/15.
//
//

#import "iTermOrphanServerAdopter.h"

#import "DebugLogging.h"
#import "NSApplication+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "PseudoTerminal.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermFileDescriptorSocketPath.h"
#import "iTermMultiServerConnection.h"
#import "iTermSessionFactory.h"
#import "iTermSessionLauncher.h"

@implementation iTermOrphanServerAdopter {
    NSArray<NSString *> *_pathsOfOrphanedMonoServers;
    NSArray<NSString *> *_pathsOfMultiServers;
    __weak PseudoTerminal *_window;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

NSArray<NSString *> *iTermOrphanServerAdopterFindMonoServers(void) {
    NSMutableArray *array = [NSMutableArray array];
    NSString *dir = [NSString stringWithUTF8String:iTermFileDescriptorDirectory()];
    for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        NSString *prefix = [NSString stringWithUTF8String:iTermFileDescriptorSocketNamePrefix];
        if ([filename hasPrefix:prefix]) {
            [array addObject:[dir stringByAppendingPathComponent:filename]];
        }
    }
    return array;
}

NSArray<NSString *> *iTermOrphanServerAdopterFindMultiServers(void) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSString *appSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSDirectoryEnumerator *enumerator =
    [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:appSupportPath]
                         includingPropertiesForKeys:nil
                                            options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                       errorHandler:nil];
    for (NSURL *url in enumerator) {
        if (![url.path.lastPathComponent stringMatchesGlobPattern:@"daemon-*.socket" caseSensitive:YES]) {
            continue;
        }
        [result addObject:url.path];
    }
    return result;
}

- (instancetype)init {
    if (![iTermAdvancedSettingsModel runJobsInServers]) {
        return nil;
    }
    if ([[NSApplication sharedApplication] isRunningUnitTests]) {
        return nil;
    }
    self = [super init];
    if (self) {
        if ([iTermAdvancedSettingsModel multiserver]) {
            _pathsOfMultiServers = iTermOrphanServerAdopterFindMultiServers();
        }
        _pathsOfOrphanedMonoServers = iTermOrphanServerAdopterFindMonoServers();
    }
    return self;
}

- (void)removePath:(NSString *)path {
    _pathsOfOrphanedMonoServers = [_pathsOfOrphanedMonoServers arrayByRemovingObject:path];
    _pathsOfMultiServers = [_pathsOfMultiServers arrayByRemovingObject:path];
}

- (void)openWindowWithOrphansWithCompletion:(void (^)(void))completion {
#warning TODO: Test this! A lot!
    dispatch_queue_t queue = dispatch_queue_create("com.iterm2.orphan-adopter", DISPATCH_QUEUE_SERIAL);
    for (NSString *path in _pathsOfOrphanedMonoServers) {
        dispatch_async(queue, ^{
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_enter(group);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self adoptMonoServerOrphanWithPath:path completion:^(PTYSession *session) {
                    dispatch_group_leave(group);
                }];
            });
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        });
    }
    for (NSString *path in _pathsOfMultiServers) {
        [self enqueueAdoptonsOfMultiServerOrphansWithPath:path queue:queue];
    }
    if (completion) {
        dispatch_async(queue, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        });
    }
}

- (void)adoptMonoServerOrphanWithPath:(NSString *)filename completion:(void (^)(PTYSession *))completion {
    DLog(@"Try to connect to orphaned server at %@", filename);
    pid_t pid = iTermFileDescriptorProcessIdFromPath(filename.UTF8String);
    if (pid < 0) {
        DLog(@"Invalid pid in filename %@", filename);
        return;
    }

    iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRun(pid);
    if (serverConnection.ok) {
        DLog(@"Restore it");
        iTermGeneralServerConnection generalConnection = {
            .type = iTermGeneralServerConnectionTypeMono,
            .mono = serverConnection
        };
        [self.delegate orphanServerAdopterOpenSessionForConnection:generalConnection
                                                          inWindow:_window
                                                        completion:^(PTYSession *session) {
            assert(dispatch_queue_get_label(dispatch_get_main_queue()) == dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL));
            if (!self->_window) {
                self->_window = [[iTermController sharedInstance] terminalWithSession:session];
            }
            completion(session);
        }];
    } else {
        DLog(@"Failed: %s", serverConnection.error);
        completion(nil);
    }
}

- (void)enqueueAdoptonsOfMultiServerOrphansWithPath:(NSString *)filename queue:(dispatch_queue_t)queue {
    DLog(@"Try to connect to multiserver at %@", filename);
    NSString *basename = filename.lastPathComponent.stringByDeletingPathExtension;
    NSString *const prefix = @"daemon-";
    assert([basename hasPrefix:prefix]);
    NSString *numberAsString = [basename substringFromIndex:prefix.length];
    NSScanner *scanner = [NSScanner scannerWithString:numberAsString];
    NSInteger number = -1;
    if (![scanner scanInteger:&number]) {
        return;
    }
    iTermMultiServerConnection *connection = [iTermMultiServerConnection connectionForSocketNumber:number
                                                                                  createIfPossible:NO];
    if (connection == nil) {
        NSLog(@"Failed to connect to %@", filename);
        return;
    }

    NSArray<iTermFileDescriptorMultiClientChild *> *children = [connection.unattachedChildren copy];
    for (iTermFileDescriptorMultiClientChild *child in children) {
        iTermGeneralServerConnection generalConnection = {
            .type = iTermGeneralServerConnectionTypeMulti,
            .multi = {
                .pid = child.pid,
                .number = number
            }
        };
        dispatch_async(queue, ^{
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_enter(group);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate orphanServerAdopterOpenSessionForConnection:generalConnection
                                                                  inWindow:self->_window
                                                                completion:^(PTYSession *session) {
                                                                    if (!self->_window) {
                                                                        self->_window = [[iTermController sharedInstance] terminalWithSession:session];
                                                                    }
                                                                    dispatch_group_leave(group);
                                                                }];
            });
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        });
    }
}

#pragma mark - Properties

- (BOOL)haveOrphanServers {
    return _pathsOfOrphanedMonoServers.count > 0;
}

@end

