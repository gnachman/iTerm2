//
//  iTermOrphanServerAdopter.m
//  iTerm2
//
//  Created by George Nachman on 6/7/15.
//
//

#import "iTermOrphanServerAdopter.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermFileDescriptorSocketPath.h"
#import "iTermSessionFactory.h"
#import "iTermSessionLauncher.h"
#import "NSApplication+iTerm.h"
#import "NSArray+iTerm.h"
#import "PseudoTerminal.h"

@implementation iTermOrphanServerAdopter {
    NSMutableArray *_pathsToOrphanedServerSockets;
    PseudoTerminal *_window;  // weak
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
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
        _pathsToOrphanedServerSockets = [[self findOrphanServers] retain];
    }
    return self;
}

- (void)dealloc {
    [_pathsToOrphanedServerSockets release];
    [super dealloc];
}

- (NSMutableArray *)findOrphanServers {
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

- (void)removePath:(NSString *)path {
    [_pathsToOrphanedServerSockets removeObject:path];
}

- (void)openWindowWithOrphansWithCompletion:(void (^)(void))completion {
    [self openWindowWithOrphansFromPaths:_pathsToOrphanedServerSockets
                              completion:completion];
}

- (void)openWindowWithOrphansFromPaths:(NSArray<NSString *> *)paths
                            completion:(void (^)(void))completion {
    NSString *path = paths.firstObject;
    if (!path) {
        self->_window = nil;
        if (completion) {
            completion();
        }
        return;
    }
    NSArray<NSString *> *tail = [paths subarrayFromIndex:1];

    NSLog(@"--- Begin orphan %@", path);
    [self adoptOrphanWithPath:path completion:^(PTYSession *session) {
        NSLog(@"--- End orphan");
        [self openWindowWithOrphansFromPaths:tail
                                  completion:completion];
    }];
}

- (void)adoptOrphanWithPath:(NSString *)filename completion:(void (^)(PTYSession *session))completion {
    DLog(@"Try to connect to orphaned server at %@", filename);
    pid_t pid = iTermFileDescriptorProcessIdFromPath(filename.UTF8String);
    if (pid < 0) {
        DLog(@"Invalid pid in filename %@", filename);
        return;
    }

    iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRun(pid);
    if (serverConnection.ok) {
        DLog(@"Restore it");
        if (_window) {
            [self openOrphanedSession:serverConnection inWindow:_window completion:completion];
        } else {
            [self openOrphanedSession:serverConnection inWindow:nil completion:^(PTYSession *session) {
                self->_window = [[iTermController sharedInstance] terminalWithSession:session];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(session);
                });
            }];
        }
    } else {
        DLog(@"Failed: %s", serverConnection.error);
        completion(nil);
    }
}

- (void)openOrphanedSession:(iTermFileDescriptorServerConnection)serverConnection
                   inWindow:(PseudoTerminal *)desiredWindow
                 completion:(void (^)(PTYSession *session))completion {
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    Profile *defaultProfile = [[ProfileModel sharedInstance] defaultBookmark];

    [iTermSessionLauncher launchBookmark:nil
                              inTerminal:desiredWindow
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:NO
                             canActivate:NO
                      respectTabbingMode:NO
                                 command:nil
                             makeSession:^(Profile *profile, PseudoTerminal *term, void (^makeSessionCompletion)(PTYSession *)) {
        iTermFileDescriptorServerConnection theServerConnection = serverConnection;
        PTYSession *session = [[term.sessionFactory newSessionWithProfile:defaultProfile] autorelease];
        [term addSessionInNewTab:session];
        const BOOL ok = [term.sessionFactory attachOrLaunchCommandInSession:session
                                                                  canPrompt:NO
                                                                 objectType:iTermWindowObject
                                                           serverConnection:&theServerConnection
                                                                  urlString:nil
                                                               allowURLSubs:NO
                                                                environment:@{}
                                                                customShell:[ITAddressBookMgr customShellForProfile:defaultProfile]
                                                                     oldCWD:nil
                                                             forceUseOldCWD:NO
                                                                    command:nil
                                                                     isUTF8:nil
                                                              substitutions:nil
                                                           windowController:term
                                                                synchronous:NO
                                                                 completion:nil];
        makeSessionCompletion(ok ? session : nil);
    }
                             synchronous:NO
                          didMakeSession:^(PTYSession *aSession) {
        NSLog(@"restored an orphan");
        [aSession showOrphanAnnouncement];
        completion(aSession);
    }
                              completion:nil];
}

#pragma mark - Properties

- (BOOL)haveOrphanServers {
    return _pathsToOrphanedServerSockets.count > 0;
}

@end
