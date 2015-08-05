//
//  iTermOrphanServerAdopter.m
//  iTerm2
//
//  Created by George Nachman on 6/7/15.
//
//

#import "iTermOrphanServerAdopter.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermFileDescriptorSocketPath.h"
#import "NSApplication+iTerm.h"
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

- (void)openWindowWithOrphans {
    for (NSString *path in _pathsToOrphanedServerSockets) {
        [self adoptOrphanWithPath:path];
    }
    _window = nil;
}

- (void)adoptOrphanWithPath:(NSString *)filename {
    NSLog(@"Try to connect to orphaned server at %@", filename);
    pid_t pid = iTermFileDescriptorProcessIdFromPath(filename.UTF8String);
    if (pid < 0) {
        NSLog(@"Invalid pid in filename %@", filename);
        return;
    }

    iTermFileDescriptorServerConnection serverConnection = iTermFileDescriptorClientRun(pid);
    if (serverConnection.ok) {
        NSLog(@"Restore it");
        if (_window) {
            [self openOrphanedSession:serverConnection inWindow:_window];
        } else {
            PTYSession *session = [self openOrphanedSession:serverConnection inWindow:nil];
            _window = [[iTermController sharedInstance] terminalWithSession:session];
        }
    } else {
        NSLog(@"Failed: %s", serverConnection.error);
    }
}

- (PTYSession *)openOrphanedSession:(iTermFileDescriptorServerConnection)serverConnection
                           inWindow:(PseudoTerminal *)desiredWindow {
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    Profile *defaultProfile = [[ProfileModel sharedInstance] defaultBookmark];
    PTYSession *aSession =
        [[iTermController sharedInstance] launchBookmark:nil
                                              inTerminal:desiredWindow
                                                 withURL:nil
                                                isHotkey:NO
                                                 makeKey:NO
                                                 command:nil
                                                   block:^PTYSession *(PseudoTerminal *term) {
                                                       iTermFileDescriptorServerConnection theServerConnection = serverConnection;
                                                       term.disablePromptForSubstitutions = YES;
                                                       return [term createSessionWithProfile:defaultProfile
                                                                                     withURL:nil
                                                                               forObjectType:iTermWindowObject
                                                                            serverConnection:&theServerConnection];
                                                   }];
    NSLog(@"restored an orphan");
    [aSession showOrphanAnnouncement];
    return aSession;
}

#pragma mark - Properties

- (BOOL)haveOrphanServers {
    return _pathsToOrphanedServerSockets.count > 0;
}

@end
