//
//  SCPFile.m
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "SCPFile.h"
#import <NMSSH/NMSSH.h>
#import <NMSSH/NMSSHConfig.h>
#import <NMSSH/NMSSHHostConfig.h>
#import <NMSSH/libssh2.h>

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermSlowOperationGateway.h"
#import "iTermOpenDirectory.h"
#import "iTermWarning.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "ProfileModel.h"

@interface NMSSHSession(iTerm)
@property (atomic, readonly) void *agent;
@end

static NSString *const kSCPFileErrorDomain = @"com.googlecode.iterm2.SCPFile";
static NSString *const kSecureCopyConnectionFailedWarning = @"NoSyncSecureCopyConnectionFailedWarning";

static NSError *SCPFileError(NSString *description) {
    return [NSError errorWithDomain:kSCPFileErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

@interface iTermAuthSock: NSObject
@property (nonatomic, readonly) NSString *authSock;
+ (instancetype)sharedInstance;
@end

@implementation iTermAuthSock {
    NSString *_authSock;
    dispatch_group_t _group;
}

+ (instancetype)sharedInstance {
    static iTermAuthSock *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (NSString *)authSock {
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    NSString *shell = [ITAddressBookMgr customShellForProfile:profile] ?: [iTermOpenDirectory userShell] ?:  @"/bin/bash";
    dispatch_group_t group;
    BOOL request = NO;
    @synchronized(self) {
        if (_authSock) {
            return _authSock;
        }
        if (!_group) {
            _group = dispatch_group_create();
            request = YES;
        }
        group = _group;
    }
    if (request) {
        dispatch_group_enter(group);
        DLog(@"Try to get the value of $SSH_AUTH_SOCK");
        [[iTermSlowOperationGateway sharedInstance] exfiltrateEnvironmentVariableNamed:@"SSH_AUTH_SOCK"
                                                                                 shell:shell
                                                                            completion:^(NSString * _Nonnull value) {
            @synchronized(self) {
                self->_authSock = value;
            }
            dispatch_group_leave(group);
            DLog(@"Value is %@", value);
        }];
    }
    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW,
                                             0.5 * NSEC_PER_SEC));
    @synchronized(self) {
        DLog(@"Return %@", _authSock);
        return _authSock;
    }
}

@end

@interface SCPFile () <NMSSHSessionDelegate>
@property(atomic, strong) NMSSHSession *session;
@property(atomic, assign) BOOL stopped;
@property(atomic, copy) NSString *error;
@property(atomic, copy) NSString *destination;
@property(nonatomic, assign) dispatch_queue_t queue;
@end

@implementation SCPFile {
    BOOL _okToAdd;
    BOOL _downloading;
    dispatch_queue_t _queue;
    NSString *_homeDirectory;
    NSString *_userName;
    NSString *_hostName;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.googlecode.iterm2.SCPFile", NULL);
        _homeDirectory = [NSHomeDirectory() copy];
        _userName = [NSUserName() copy];
        _hostName = [[[NSHost currentHost] name] copy];

    }
    return self;
}

- (NSError *)lastError {
  if (self.session.rawSession) {
    return self.session.lastError;
  } else {
    // The reported error is meaningless without a raw session.
    return nil;
  }
}

- (void)setQueue:(dispatch_queue_t)queue {
    @synchronized(self) {
        if (queue != _queue) {
            _queue = queue;
        }
    }
}

- (dispatch_queue_t)queue {
    @synchronized(self) {
        return _queue;
    }
}

- (NSString *)displayName {
    return [NSString stringWithFormat:@"Secure copy\nUser name: %@\nHost: %@\nFile: %@", _path.username, _path.hostname, _path.path];
}

- (NSString *)shortName {
    return [[self.path.path pathComponents] lastObject];
}

- (NSString *)subheading {
    return [NSString stringWithFormat:@"%@@%@:%@", self.path.username, self.path.hostname, self.path.path];
}

+ (NSString *)fileNameForPath:(NSString *)path {
    NSArray *components = [path pathComponents];
    if (!components.count) {
        return nil;
    }
    return [components lastObject];
}

- (NSString *)authRequestor {
    return [NSString stringWithFormat:@"%@@%@", _path.username, _path.hostname];
}

- (NSString *)protocolName {
    return @"secure copy";
}

// This runs in a thread.
- (void)performTransferWrapper:(BOOL)isDownload {
    [self performTransfer:isDownload];
    if (self.session && self.session.isConnected) {
        [self.session disconnect];
    }
    self.session = nil;
}

- (NSString *)hostname {
    NSArray *hostComponents = [self.path.hostname componentsSeparatedByString:@":"];
    NSInteger components = [hostComponents count];

    // Check if the host is {hostname}:{port} or {IPv4}:{port}
    if (components == 2) {
        return hostComponents[0];
    } else if (components >= 4 &&
               [hostComponents[0] hasPrefix:@"["] &&
               [hostComponents[components-2] hasSuffix:@"]"]) {
        // Is [{IPv6}]:{port}, return just {IPv6}.
        hostComponents = [hostComponents subarrayWithRange:NSMakeRange(0, components - 1)];
        NSString *bracketedHostname = [hostComponents componentsJoinedByString:@":"];
        return [bracketedHostname substringWithRange:NSMakeRange(1, bracketedHostname.length - 2)];
    }

    return self.path.hostname;
}

- (int)port {
    NSArray *hostComponents = [self.path.hostname componentsSeparatedByString:@":"];
    NSInteger components = [hostComponents count];

    // Check if the host is {hostname}:{port} or {IPv4}:{port}
    if (components == 2) {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]];

        return [[formatter numberFromString:[hostComponents lastObject]] intValue];
    } else if (components >= 4 &&
               [hostComponents[0] hasPrefix:@"["] &&
               [hostComponents[components-2] hasSuffix:@"]"]) {
        // Check if the host is [{IPv6}]:{port}
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]];

        return [[formatter numberFromString:[hostComponents lastObject]] intValue];
    }

    // If no port was defined, use 22 by default
    return 22;
}

- (BOOL)privateKeyIsEncrypted:(NSString *)filename {
    @autoreleasepool {
        NSString *privateKey = [NSString stringWithContentsOfFile:filename
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil];
        for (NSString *string in @[@"-----BEGIN OPENSSH PRIVATE KEY-----", @"ENCRYPTED"]) {
            if ([privateKey rangeOfString:string].location != NSNotFound) {
                return YES;
            }
        }
    }
    return NO;
}

// This runs in a thread
- (NSArray *)configs {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *appSupport = [fileManager applicationSupportDirectory];
    NSArray *paths = @[ [appSupport stringByAppendingPathComponent:@"ssh_config"] ?: @"",
                        [@"~/.ssh/config" stringByExpandingTildeInPath] ?: @"",
                        @"/etc/ssh/ssh_config",
                        @"/etc/ssh_config" ];
    NSMutableArray *configs = [NSMutableArray array];
    for (NSString *path in paths) {
        if (path.length == 0) {
            DLog(@"Zero length path in configs paths %@", paths);
            continue;
        }
        if ([fileManager fileExistsAtPath:path]) {
            NMSSHConfig *config = [NMSSHConfig configFromFile:path];
            if (config) {
                [configs addObject:config];
            } else {
                XLog(@"Could not parse config file at %@", path);
            }
        }
    }
    return configs;
}

// This runs in a thread
- (NSString *)filenameByExpandingMetasyntacticVariables:(NSString *)filename {
    filename = [filename stringByExpandingTildeInPath];
    NSDictionary *substitutions =
        @{ @"%d": _homeDirectory,
           @"%u": _userName,
           @"%l": _hostName,
           @"%h": self.session.host,
           @"%r": self.session.username };
    for (NSString *metavar in substitutions) {
        filename = [filename stringByReplacingOccurrencesOfString:metavar
                                                       withString:substitutions[metavar]];
    }
    return filename;
}

- (void)performTransfer:(BOOL)isDownload {
    [self performTransfer:isDownload agentAllowed:YES];
}

// Don't call this on the main thread!
- (NSString *)keyboardInteractiveRequest:(NSString *)prompt {
    __block NSString *value = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_main_queue(), ^() {
        [[FileTransferManager sharedInstance] transferrableFile:self
                                              interactivePrompt:prompt
                                                     completion:^(NSString *result) {
                                                         value = [result copy];
                                                         dispatch_group_leave(group);
                                                     }];
    });
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    return value;
}

- (NSURL *)sessionURL {
    assert(self.session);
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.host = self.session.host;
    components.user = self.session.username;
    components.port = self.session.port;
    components.path = self.path.path;
    components.scheme = @"ssh";
    return components.URL;
}

// This runs in a thread.
- (void)performTransfer:(BOOL)isDownload agentAllowed:(BOOL)agentAllowed {
    NSString *baseName = [[self class] fileNameForPath:self.path.path];
    DLog(@"performTransfer download=%@ agentAllowed=%@ path=%@ baseName=%@",
         @(isDownload), @(agentAllowed), self.path, baseName);
    if (!baseName) {
        self.error = [NSString stringWithFormat:@"Invalid path: %@", self.path.path];
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:SCPFileError(@"Invalid filename")];
        });
        return;
    }
    _okToAdd = NO;
    int effectivePort;
    if (self.session) {
        self.session.delegate = self;
        effectivePort = self.session.port.intValue;
    } else {
        DLog(@"Create seession to hostname=%@ configs=%@ port=%@ username=%@",
             [self hostname], [self configs], @([self port]), self.path.username);
        self.session = [[NMSSHSession alloc] initWithHost:[self hostname]
                                                  configs:[self configs]
                                          withDefaultPort:[self port]
                                          defaultUsername:self.path.username];
        effectivePort = self.session.port.intValue;
        self.session.delegate = self;
        [self.session connect];
        if (self.stopped) {
            XLog(@"Stop after connect");
            dispatch_sync(dispatch_get_main_queue(), ^() {
                [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
            });
            return;
        }
    }
    NSURL *url = [self sessionURL];
    if (!self.session.isConnected) {
        DLog(@"Not connected");
        NSError *theError = [self lastError];
        if (!theError) {
            // If connection fails, there is no rawSession in NMSSHSession, so it can't return an
            // error. Should that ever change, this clause will not execute.
            theError = [NSError errorWithDomain:@"com.googlecode.iterm2"
                                           code:-1
                                       userInfo:@{ NSLocalizedDescriptionKey: @"Could not connect." }];
        }
        self.error = [NSString stringWithFormat:@"Connection failed: %@",
                         theError.localizedDescription];
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:theError];
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Failed to connect to %@:%d. Double-check that the host name is correct.", self.hostname, effectivePort]
                                           actions:@[ @"Ok", @"Help" ]
                                     actionMapping:nil
                                         accessory:nil
                                        identifier:kSecureCopyConnectionFailedWarning
                                       silenceable:kiTermWarningTypePermanentlySilenceable
                                           heading:@"Connection Failed"
                                       cancelLabel:@"Help"
                                            window:nil];
            if (selection == kiTermWarningSelection1) {
                [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/troubleshoot-hostname"]];
            }
        });
        return;
    }

    BOOL didConnectToAgent = NO;
    if (agentAllowed && !self.hasPredecessor) {
        DLog(@"Connect to agent");
        self.session.authSock = [[iTermAuthSock sharedInstance] authSock];
        [self.session connectToAgent];
        // Check a private property to see if the connection to the agent was made.
        if ([self.session respondsToSelector:@selector(agent)]) {
            didConnectToAgent = [self.session agent] != nil;
        }
    }

    if (!self.session.isAuthorized) {
        DLog(@"Authenticate");
        NSArray *authTypes = [self.session supportedAuthenticationMethods];
        if (!authTypes) {
            authTypes = @[ @"password" ];
        }
        for (NSString *authType in authTypes) {
            if (self.stopped) {
                XLog(@"Break out of auth loop because stopped");
                break;
            }
            if (!self.session.session) {
                XLog(@"Break out of auth loop because disconnected");
                break;
            }
            if ([authType isEqualToString:@"password"]) {
                NSString *password = [self keyboardInteractiveRequest:@"password"];
                if (self.stopped || !password) {
                    break;
                }
                [self.session authenticateByPassword:password];
                if (self.session.isAuthorized) {
                    break;
                }
            } else if ([authType isEqualToString:@"keyboard-interactive"]) {
                [self.session authenticateByKeyboardInteractiveUsingBlock:^NSString *(NSString *request) {
                    return [self keyboardInteractiveRequest:request];
                }];
                if (self.stopped || self.session.isAuthorized) {
                    break;
                }
            } else if ([authType isEqualToString:@"publickey"]) {
                if (self.stopped) {
                    break;
                }

                NSMutableArray *keyPaths = [NSMutableArray array];
                if (self.session.hostConfig.identityFiles.count) {
                    [keyPaths addObjectsFromArray:self.session.hostConfig.identityFiles];
                } else {
                    [keyPaths addObjectsFromArray:@[ @"~/.ssh/id_rsa",
                                                     @"~/.ssh/id_dsa",
                                                     @"~/.ssh/id_ecdsa",
                                                     @"~/.ssh/id_ed25519" ]];
                }
                NSFileManager *fileManager = [NSFileManager defaultManager];
                for (NSString *iteratedKeyPath in keyPaths) {
                    NSString *keyPath = [self filenameByExpandingMetasyntacticVariables:iteratedKeyPath];
                    if (![fileManager fileExistsAtPath:keyPath]) {
                        XLog(@"No key file at %@", keyPath);
                        continue;
                    }
                    NSString *password = nil;
                    if ([self privateKeyIsEncrypted:keyPath]) {
                        NSString *prompt = [NSString stringWithFormat:@"passphrase for private key “%@”:",
                                            keyPath];
                        password = [self keyboardInteractiveRequest:prompt];
                    }
                    XLog(@"Attempting to authenticate with key %@", keyPath);
                    NSString *publicKeyPath = [keyPath stringByAppendingString:@".pub"];
                    if (![[NSFileManager defaultManager] fileExistsAtPath:publicKeyPath]) {
                        XLog(@"Warning: no public key at %@. Trying to authenticate with only a private key.", publicKeyPath);
                        publicKeyPath = nil;
                    }
                    [self.session authenticateByPublicKey:publicKeyPath
                                               privateKey:keyPath
                                              andPassword:password];

                    if (self.session.isAuthorized) {
                        XLog(@"Authorized!");
                        break;
                    }

                    if (!self.session.session) {
                        XLog(@"Disconnected!");
                        break;
                    }
                }
                if (self.session.isAuthorized) {
                    break;
                }
            }
        }
    }
    if (self.stopped) {
        XLog(@"Stop after auth");
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
        });
        return;
    }
    if (!self.session.session && didConnectToAgent) {
        DLog(@"Retry without agent");
        // Try again without agent. I got into a state where using the agent prevented connections
        // from going through.
        [self.session disconnect];
        self.session = nil;
        [self performTransfer:isDownload agentAllowed:NO];
        return;
    }
    if (!self.session.isAuthorized) {
        DLog(@"Still not authenticated.");
        __block NSError *error = [self lastError];
        dispatch_sync(dispatch_get_main_queue(), ^() {
            if (!error) {
                error = [NSError errorWithDomain:@"com.googlecode.iterm2.SCPFile"
                                            code:0
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Authentication failed." }];
            }
            self.error = @"Authentication error.";
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        });
        return;
    }

    if (_okToAdd) {
        DLog(@"Add %@:%@ to known hosts", self.session.host, self.session.port);
        [self.session addKnownHostName:self.session.host
                                  port:[self.session.port intValue]
                                toFile:nil
                              withSalt:nil];
    }

    if (isDownload) {
        DLog(@"Will download");
        NSString *downloadDirectory = [[NSFileManager defaultManager] downloadsDirectory];
        NSString *tempfile = nil;
        NSString *tempFileName = [self tempFileName];
        if (downloadDirectory) {
            tempfile = [downloadDirectory stringByAppendingPathComponent:tempFileName];
        }
        if (!tempfile) {
            self.error = [NSString stringWithFormat:@"Downloads folder not writable. Tried %@",
                          downloadDirectory];
            dispatch_sync(dispatch_get_main_queue(), ^() {
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(@"Downloads folder not writable")];
            });
            return;
        }
        self.destination = tempfile;
        self.status = kTransferrableFileStatusTransferring;
        __block BOOL quarantined = NO;
        __block BOOL quarantineError = NO;
        BOOL ok = [self.session.channel downloadFile:self.path.path
                                                  to:tempfile
                                            progress:^BOOL (NSUInteger bytes, NSUInteger fileSize) {
            if (!quarantined) {
                if (![self quarantine:tempfile sourceURL:url]) {
                    quarantineError = YES;
                    DLog(@"Quarantine error");
                    return NO;
                }
                quarantined = YES;
            }
            self.bytesTransferred = bytes;
            self.fileSize = fileSize;
            dispatch_sync(dispatch_get_main_queue(), ^() {
                if (!self.stopped) {
                    [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
                }
            });
            if (self.stopped) {
                XLog(@"Stopping mid-download");
            }
            return !self.stopped;
        }];
        if (!quarantined && [[NSFileManager defaultManager] fileExistsAtPath:tempfile]) {
            DLog(@"Apparently a zero byte file");
            // Zero-byte file, presumably.
            if (![self quarantine:tempfile sourceURL:url]) {
                quarantineError = YES;
                DLog(@"Quarantine failed");
                ok = NO;
            } else {
                quarantined = YES;
            }
        }
        __block NSError *error = nil;
        __block NSString *finalDestination = nil;
        if (ok) {
            DLog(@"Download OK");
            error = nil;
            // We determine the filename and perform the move in the main thread to avoid two
            // threads trying to determine the final destination at the same time.
            dispatch_sync(dispatch_get_main_queue(), ^() {
                finalDestination = [self finalDestinationForPath:baseName
                                            destinationDirectory:downloadDirectory];
                if ([[NSFileManager defaultManager] fileExistsAtPath:finalDestination]) {
                    [[NSFileManager defaultManager] replaceItemAtURL:[NSURL fileURLWithPath:finalDestination]
                                                       withItemAtURL:[NSURL fileURLWithPath:tempfile]
                                                      backupItemName:nil
                                                             options:0
                                                    resultingItemURL:nil
                                                               error:&error];
                } else {
                    [[NSFileManager defaultManager] moveItemAtPath:tempfile
                                                            toPath:finalDestination
                                                             error:&error];
                }
            });
            if (error) {
                self.error = error.localizedDescription;
                DLog(@"%@", error);
            }
            [[NSFileManager defaultManager] removeItemAtPath:tempfile error:NULL];
            self.destination = finalDestination;
        } else {
            DLog(@"Download failed.");
            const BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:tempfile error:&error];
            DLog(@"Remove %@: %@", tempfile, error);
            if (quarantineError && (!ok || error)) {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [self failedToRemoveUnquarantinedFileAt:tempfile];
                });
            }
            if (self.stopped) {
                dispatch_sync(dispatch_get_main_queue(), ^() {
                    [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
                });
                return;
            } else {
                if (quarantineError) {
                    self.error = @"Quarantine Error";
                } else {
                    NSString *errorDescription = [[self lastError] localizedDescription];
                    if (errorDescription.length) {
                        self.error = errorDescription;
                    } else {
                        self.error = @"Download failed";
                    }
                }
                error = SCPFileError(@"Download failed");
            }
        }
        dispatch_sync(dispatch_get_main_queue(), ^() {
            if (!error) {
                self.localPath = finalDestination;
            }
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        });
        if (!error && self.successor) {
            SCPFile *scpSuccessor = (SCPFile *)self.successor;
            scpSuccessor.session = self.session;
            scpSuccessor.queue = _queue;
            self.session = nil;
            self.queue = nil;
            [scpSuccessor performTransferWrapper:isDownload];
        }
    } else {
        DLog(@"Will upload");
        self.status = kTransferrableFileStatusTransferring;
        DLog(@"Upload “%@” to “%@”", [self localPath], self.path.path);
        BOOL ok = [self.session.channel uploadFile:[self localPath]
                                                to:self.path.path
                                          progress:^BOOL (NSUInteger bytes) {
                                              self.bytesTransferred = bytes;
                                              dispatch_sync(dispatch_get_main_queue(), ^() {
                                                  if (!self.stopped) {
                                                      [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
                                                  }
                                              });
                                              return !self.stopped;
                                          }];
        NSError *error;
        if (ok) {
            DLog(@"Upload OK");
            error = nil;
        } else {
            DLog(@"Upload failed: %@", error);
            if (self.stopped) {
                dispatch_sync(dispatch_get_main_queue(), ^() {
                    [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
                });
                return;
            } else {
                NSString *errorDescription = [[self lastError] localizedDescription];
                if (errorDescription.length) {
                    self.error = errorDescription;
                } else {
                    self.error = @"Upload failed";
                }
                error = SCPFileError(@"Upload failed");
            }
        }
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        });
        if (!error && self.successor) {
            SCPFile *scpSuccessor = (SCPFile *)self.successor;
            scpSuccessor.session = self.session;
            scpSuccessor.queue = _queue;
            self.session = nil;
            self.queue = nil;
            [scpSuccessor performTransferWrapper:isDownload];
        }
    }
}

- (NSString *)tempFileName {
    NSString *result = [NSString stringWithFormat:@".iTerm2.%@", [NSString uuid]];

    return result;
}

- (void)download {
    _downloading = YES;
    self.status = kTransferrableFileStatusStarting;
    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];

    if (!self.hasPredecessor) {
        dispatch_async(_queue, ^() {
            [self performTransferWrapper:YES];
        });
    }
}

- (void)upload {
    _downloading = NO;
    self.status = kTransferrableFileStatusStarting;
    self.fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.localPath error:nil] fileSize];
    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];

    if (!self.hasPredecessor) {
        dispatch_async(_queue, ^() {
            [self performTransferWrapper:NO];
        });
    }
}

- (BOOL)isDownloading {
    return _downloading;
}
- (void)stop {
    [[FileTransferManager sharedInstance] transferrableFileWillStop:self];
    self.stopped = YES;
}

- (BOOL)session:(NMSSHSession *)session shouldConnectToHostWithFingerprint:(NSString *)fingerprint {
    // It's not necessary to initialize result but it makes the analyzer shut up.
    __block BOOL result = NO;
    dispatch_sync(dispatch_get_main_queue(), ^(void) {
        _okToAdd = NO;
        NSString *message = nil;
        NSString *title = @"Notice";  // The default value should never be used.
        switch ([self.session knownHostStatusInFiles:nil]) {
            case NMSSHKnownHostStatusFailure:
                title = [NSString stringWithFormat:@"Problem connecting to %@", session.host];
                message = [NSString stringWithFormat:@"Could not read the known_hosts file.\n"
                                                     @"As a result, the authenticity of host '%@' can't be established."
                                                     @"DSA key fingerprint is %@. Connect anyway?",
                           session.host, fingerprint];
                break;

            case NMSSHKnownHostStatusMatch:
                result = YES;
                message = nil;
                break;

            case NMSSHKnownHostStatusMismatch:
                title = @"Warning!";
                message =
                    [NSString stringWithFormat:@"REMOTE HOST IDENTIFICATION HAS CHANGED!\n\n"
                                               @"The DSA key fingerprint of host '%@' has changed. It is %@.\n\n"
                                               @"Someone could be eavesdropping on you right now (man-in-the-middle attack)!\n"
                                               @"It is also possible that a host key has just been changed.\nConnect anyway?",
                     session.host, fingerprint];
                break;

            case NMSSHKnownHostStatusNotFound:
                title = [NSString stringWithFormat:@"First time connecting to %@", session.host];
                message =
                    [NSString stringWithFormat:@"The authenticity of host '%@' can't be established.\n\n"
                                               @"DSA key fingerprint is %@.\n\nConnect anyway?",
                        session.host, fingerprint];
                _okToAdd = YES;
                break;
        }
        if (message) {
            result = [[FileTransferManager sharedInstance] transferrableFile:self
                                                                       title:title
                                                              confirmMessage:message];
        }
    });
    return result;
}

- (NSString *)session:(NMSSHSession *)session keyboardInteractiveRequest:(NSString *)request {
    __block NSString *string;
    dispatch_sync(dispatch_get_main_queue(), ^() {
        string = [self keyboardInteractiveRequest:request];
    });
    return string;
}

@end
