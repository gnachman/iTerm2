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
#import "iTermMultiServerJobManager.h"
#import "iTermSessionFactory.h"
#import "iTermSessionLauncher.h"

@implementation iTermOrphanServerAdopter {
    NSArray<NSString *> *_pathsOfOrphanedMonoServers;
    NSArray<NSString *> *_pathsOfMultiServers;
    dispatch_group_t _group;
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

static void iTermOrphanServerAdopterFindMonoServers(void (^completion)(NSArray<NSString *> *)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *array = [NSMutableArray array];
        NSString *dir = [NSString stringWithUTF8String:iTermFileDescriptorDirectory()];
        for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
            NSString *prefix = [NSString stringWithUTF8String:iTermFileDescriptorSocketNamePrefix];
            if ([filename hasPrefix:prefix]) {
                [array addObject:[dir stringByAppendingPathComponent:filename]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(array);
        });
    });
}

static void iTermOrphanServerAdopterFindMultiServers(void (^completion)(NSArray<NSString *> *)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray<NSString *> *result = [NSMutableArray array];
        NSString *appSupportPath = [[NSFileManager defaultManager] applicationSupportDirectory];
        NSDirectoryEnumerator *enumerator =
        [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:appSupportPath]
                             includingPropertiesForKeys:nil
                                                options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                           errorHandler:nil];
        for (NSURL *url in enumerator) {
            if (![url.path.lastPathComponent stringMatchesGlobPattern:@"iterm2-daemon-*.socket" caseSensitive:YES]) {
                continue;
            }
            [result addObject:url.path];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    });
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
        _group = dispatch_group_create();
        if ([iTermMultiServerJobManager available]) {
            dispatch_group_enter(_group);
            iTermOrphanServerAdopterFindMultiServers(^(NSArray<NSString *> *paths) {
                DLog(@"Have found multiservers at %@", paths);
                self->_pathsOfMultiServers = paths;
                dispatch_group_leave(self->_group);
            });
        }
        dispatch_group_enter(_group);
        iTermOrphanServerAdopterFindMonoServers(^(NSArray<NSString *> *paths) {
            DLog(@"Have found monoservers at %@", paths);
            self->_pathsOfOrphanedMonoServers = paths;
            dispatch_group_leave(self->_group);
        });
    }
    return self;
}

- (void)removePath:(NSString *)path {
    _pathsOfOrphanedMonoServers = [_pathsOfOrphanedMonoServers arrayByRemovingObject:path];
    _pathsOfMultiServers = [_pathsOfMultiServers arrayByRemovingObject:path];
}

- (void)openWindowWithOrphansWithCompletion:(void (^)(void))completion {
    dispatch_group_notify(_group, dispatch_get_main_queue(), ^{
        [self reallyOpenWindowWithOrphansWithCompletion:completion];
    });
}

- (void)reallyOpenWindowWithOrphansWithCompletion:(void (^)(void))completion {
    DLog(@"Orphan adoption beginning");
    dispatch_group_t group = dispatch_group_create();
    for (NSString *path in _pathsOfOrphanedMonoServers) {
        dispatch_group_enter(group);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self adoptMonoServerOrphanWithPath:path completion:^(PTYSession *session) {
                dispatch_group_leave(group);
            }];
        });
    }
    for (NSString *path in _pathsOfMultiServers) {
        dispatch_group_enter(group);
        [self enqueueAdoptionsOfMultiServerOrphansWithPath:path completion:^{
            dispatch_group_leave(group);
        }];
    }
    if (completion) {
        dispatch_group_notify(group, dispatch_get_main_queue(), completion);
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

- (void)enqueueAdoptionsOfMultiServerOrphansWithPath:(NSString *)filename completion:(void (^)(void))completion {
    DLog(@"Try to connect to multiserver at %@", filename);
    NSString *basename = filename.lastPathComponent.stringByDeletingPathExtension;
    NSString *const prefix = @"iterm2-daemon-";
    assert([basename hasPrefix:prefix]);
    NSString *numberAsString = [basename substringFromIndex:prefix.length];
    NSScanner *scanner = [NSScanner scannerWithString:numberAsString];
    NSInteger number = -1;
    if (![scanner scanInteger:&number]) {
        return;
    }
    DLog(@"iTermOrphanServerAdopter: get connection for multiserver socket %@", @(number));
    [iTermMultiServerConnection getConnectionForSocketNumber:number
                                            createIfPossible:NO
                                                    callback:[iTermThread.main newCallbackWithBlock:^(iTermMainThreadState *state, iTermResult<iTermMultiServerConnection *> *result) {
        [result handleObject:^(iTermMultiServerConnection * _Nonnull connection) {
            [self didEstablishMultiserverConnection:connection
                                       socketNumber:number
                                              state:state
                                         completion:completion];
        } error:^(NSError * _Nonnull error) {
            XLog(@"Orphan server adopter: Failed to connect to %@", filename);
            completion();
        }];
    }]];
}

- (void)didEstablishMultiserverConnection:(iTermMultiServerConnection *)connection
                             socketNumber:(NSInteger)number
                                    state:(iTermMainThreadState *)state
                               completion:(void (^)(void))completion {
    dispatch_group_t group = dispatch_group_create();

    DLog(@"Multiserver adoption beginning.");
    NSArray<iTermFileDescriptorMultiClientChild *> *children = [connection.unattachedChildren copy];
    for (iTermFileDescriptorMultiClientChild *child in children) {
        iTermGeneralServerConnection generalConnection = {
            .type = iTermGeneralServerConnectionTypeMulti,
            .multi = {
                .pid = child.pid,
                .number = number
            }
        };
        dispatch_group_enter(group);
        DLog(@"Orphan server adopter wants to open session for pid %@ on socket %@", @(child.pid), @(number));
        [self.delegate orphanServerAdopterOpenSessionForConnection:generalConnection
                                                          inWindow:self->_window
                                                        completion:^(PTYSession *session) {
            if (!self->_window) {
                self->_window = [[iTermController sharedInstance] terminalWithSession:session];
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), completion);
}

- (void)adoptPartialAttachments:(NSArray<id<iTermPartialAttachment>> *)partialAttachments {
    [partialAttachments enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self.delegate orphanServerAdopterOpenSessionForPartialAttachment:obj
                                                                 inWindow:self->_window
                                                               completion:^(PTYSession *session) {
            if (!self->_window) {
                self->_window = [[iTermController sharedInstance] terminalWithSession:session];
            }
        }];
    }];
}

#pragma mark - Properties

- (BOOL)haveOrphanServers {
    return _pathsOfOrphanedMonoServers.count > 0;
}

@end

