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
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@interface NMSSHSession(iTerm)
- (id)agent;
@end

static NSString *const kSCPFileErrorDomain = @"com.googlecode.iterm2.SCPFile";

static NSError *SCPFileError(NSString *description) {
    return [NSError errorWithDomain:kSCPFileErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

@interface SCPFile () <NMSSHSessionDelegate>
@property(atomic, assign) NMSSHSession *session;
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

- (id)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.googlecode.iterm2.SCPFile", NULL);
        _homeDirectory = [NSHomeDirectory() copy];
        _userName = [NSUserName() copy];
        _hostName = [[[NSHost currentHost] name] copy];

    }
    return self;
}

- (void)dealloc {
    [_error release];
    [_destination release];
    dispatch_release(_queue);
    [_homeDirectory release];
    [_userName release];
    [_hostName release];
    [super dealloc];
}

// In NMSSH 2.0, -[NMSSHSession lastError] crashes if there is no rawSession.
// When upgrading, remove this method (the bug was fixed in January, 2014).
- (NSError *)lastError {
  if (self.session.rawSession) {
    return self.session.lastError;
  } else {
    return nil;
  }
}

- (void)setQueue:(dispatch_queue_t)queue {
    @synchronized(self) {
        if (queue != _queue) {
            dispatch_release(_queue);
            _queue = queue;
            if (queue) {
                dispatch_retain(queue);
            }
        }
    }
}

- (dispatch_queue_t)queue {
    @synchronized(self) {
        return _queue;
    }
}

- (NSString *)displayName {
    return [NSString stringWithFormat:@"scp %@@%@:%@", _path.username, _path.hostname, _path.path];
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
        NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
        [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
        
        return [[formatter numberFromString:[hostComponents lastObject]] intValue];
    } else if (components >= 4 &&
               [hostComponents[0] hasPrefix:@"["] &&
               [hostComponents[components-2] hasSuffix:@"]"]) {
        // Check if the host is [{IPv6}]:{port}
        NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
        [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
        
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
        return [privateKey rangeOfString:@"ENCRYPTED"].location != NSNotFound;
    }
}

// This runs in a thread
- (NSArray *)configs {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *appSupport = [fileManager applicationSupportDirectory];
    NSArray *paths = @[ [appSupport stringByAppendingPathExtension:@"iTerm/ssh_config"],
                        [@"~/.ssh/ssh_config" stringByExpandingTildeInPath],
                        @"/etc/ssh/ssh_config",
                        @"/etc/ssh_config" ];
    NSMutableArray *configs = [NSMutableArray array];
    for (NSString *path in paths) {
        if ([fileManager fileExistsAtPath:path]) {
            NMSSHConfig *config = [NMSSHConfig configFromFile:path];
            if (config) {
                [configs addObject:config];
            } else {
                NSLog(@"Could not parse config file at %@", path);
            }
        }
    }
    return configs;
}

// This runs in a thread
- (NSString *)filenameByExpandingMetasyntaticVariables:(NSString *)filename {
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

// This runs in a thread.
- (void)performTransfer:(BOOL)isDownload agentAllowed:(BOOL)agentAllowed {
    NSString *baseName = [[self class] fileNameForPath:self.path.path];
    if (!baseName) {
        self.error = [NSString stringWithFormat:@"Invalid path: %@", self.path.path];
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:SCPFileError(@"Invalid filename")];
        });
        return;
    }
    _okToAdd = NO;
    if (self.session) {
        self.session.delegate = self;
    } else {
        self.session = [[[NMSSHSession alloc] initWithHost:[self hostname]
                                                   configs:[self configs]
                                           withDefaultPort:[self port]
                                           defaultUsername:self.path.username] autorelease];
        self.session.delegate = self;
        [self.session connect];
        if (self.stopped) {
            NSLog(@"Stop after connect");
            dispatch_sync(dispatch_get_main_queue(), ^() {
                [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
            });
            return;
        }
    }
    if (!self.session.isConnected) {
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
        });
        return;
    }

    BOOL didConnectToAgent = NO;
    if (agentAllowed) {
        [self.session connectToAgent];
        // Check a private property to see if the connection to the agent was made.
        if ([self.session respondsToSelector:@selector(agent)]) {
            didConnectToAgent = [self.session agent] != nil;
        }
    }

    if (!self.session.isAuthorized) {
        NSArray *authTypes = [self.session supportedAuthenticationMethods];
        if (!authTypes) {
            authTypes = @[ @"password" ];
        }
        for (NSString *authType in authTypes) {
            if (self.stopped) {
                NSLog(@"Break out of auth loop because stopped");
                break;
            }
            if (!self.session.session) {
                NSLog(@"Break out of auth loop because disconnected");
                break;
            }
            if ([authType isEqualToString:@"password"]) {
                __block NSString *password;
                dispatch_sync(dispatch_get_main_queue(), ^() {
                    password = [[FileTransferManager sharedInstance] transferrableFile:self
                                                             keyboardInteractivePrompt:@"Password:"];
                });
                if (self.stopped || !password) {
                    break;
                }
                [self.session authenticateByPassword:password];
                if (self.session.isAuthorized) {
                    break;
                }
            } else if ([authType isEqualToString:@"keyboard-interactive"]) {
                [self.session authenticateByKeyboardInteractiveUsingBlock:^NSString *(NSString *request) {
                    __block NSString *response;
                    dispatch_sync(dispatch_get_main_queue(), ^() {
                        response = [[FileTransferManager sharedInstance] transferrableFile:self
                                                                 keyboardInteractivePrompt:request];
                    });
                    return response;
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
                                                     @"~/.ssh/id_ecdsa" ]];
                }
                NSFileManager *fileManager = [NSFileManager defaultManager];
                for (NSString *keyPath in keyPaths) {
                    keyPath = [self filenameByExpandingMetasyntaticVariables:keyPath];
                    if (![fileManager fileExistsAtPath:keyPath]) {
                        NSLog(@"No key file at %@", keyPath);
                        continue;
                    }
                    __block NSString *password = nil;
                    if ([self privateKeyIsEncrypted:keyPath]) {
                        dispatch_sync(dispatch_get_main_queue(), ^() {
                            NSString *prompt =
                                [NSString stringWithFormat:@"Passphrase for private key “%@”:",
                                    keyPath];
                            password = [[FileTransferManager sharedInstance] transferrableFile:self
                                                                     keyboardInteractivePrompt:prompt];
                        });
                    }
                    NSLog(@"Attempting to authenticate with key %@", keyPath);
                    [self.session authenticateByPublicKey:[keyPath stringByAppendingString:@".pub"]
                                               privateKey:keyPath
                                              andPassword:password];
                
                    if (self.session.isAuthorized) {
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
        NSLog(@"Stop after auth");
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
        });
        return;
    }
    if (!self.session.session && didConnectToAgent) {
        // Try again without agent. I got into a state where using the agent prevented connections
        // from going through.
        [self.session disconnect];
        self.session = nil;
        [self performTransfer:isDownload agentAllowed:NO];
    }
    if (!self.session.isAuthorized) {
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
        [self.session addKnownHostName:self.session.host
                                  port:[self.session.port intValue]
                                toFile:nil
                              withSalt:nil];
    }

    if (isDownload) {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory,
                                                             NSUserDomainMask,
                                                             YES);
        NSString *downloadDirectory = nil;
        NSString *tempfile = nil;
        NSString *tempFileName = [self tempFileName];
        for (NSString *path in paths) {
            if ([[NSFileManager defaultManager] isWritableFileAtPath:path]) {
                tempfile = [path stringByAppendingPathComponent:tempFileName];
                downloadDirectory = path;
                break;
            }
        }
        if (!tempfile) {
            self.error = [NSString stringWithFormat:@"Downloads folder not writable. Tried: %@",
                          paths];
            dispatch_sync(dispatch_get_main_queue(), ^() {
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(@"Downloads folder not writable")];
            });
            return;
        }
        self.destination = tempfile;
        self.status = kTransferrableFileStatusTransferring;
        BOOL ok = [self.session.channel downloadFile:self.path.path
                                                  to:tempfile
                                            progress:^BOOL (NSUInteger bytes, NSUInteger fileSize) {
                                                self.bytesTransferred = bytes;
                                                self.fileSize = fileSize;
                                                dispatch_sync(dispatch_get_main_queue(), ^() {
                                                    if (!self.stopped) {
                                                        [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
                                                    }
                                                });
                                                if (self.stopped) {
                                                    NSLog(@"Stopping mid-download");
                                                }
                                                return !self.stopped;
                                            }];
        __block NSError *error;
        __block NSString *finalDestination = nil;
        if (ok) {
            error = nil;
            // We determine the filename and perform the move in the main thread to avoid two
            // threads trying to determine the final destination at the same time.
            dispatch_sync(dispatch_get_main_queue(), ^() {
                finalDestination = [[self finalDestinationForPath:baseName
                                             destinationDirectory:downloadDirectory] retain];
                [[NSFileManager defaultManager] moveItemAtPath:tempfile
                                                        toPath:finalDestination
                                                         error:&error];
            });
            if (error) {
                self.error = [NSString stringWithFormat:@"Couldn't move %@ to %@",
                              tempfile, finalDestination];
            }
            [[NSFileManager defaultManager] removeItemAtPath:tempfile error:NULL];
            self.destination = [finalDestination autorelease];
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:tempfile error:NULL];
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
                    self.error = @"Download failed";
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
        self.status = kTransferrableFileStatusTransferring;
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
            error = nil;
        } else {
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
        NSString *message;
        switch ([self.session knownHostStatusInFiles:nil]) {
            case NMSSHKnownHostStatusFailure:
                message = [NSString stringWithFormat:@"Could not read the known_hosts file.\n"
                                                     @"As a result, the autenticity of host '%@' can't be established."
                                                     @"DSA key fingerprint is %@. Connect anyway?",
                           session.host, fingerprint];
                break;
                
            case NMSSHKnownHostStatusMatch:
                result = YES;
                message = nil;
                break;

            case NMSSHKnownHostStatusMismatch:
                message =
                    [NSString stringWithFormat:@"REMOTE HOST IDENTIFICATION HAS CHANGED!\n"
                                               @"The DSA key fingerprint of host '%@' has changed. It is %@.\n"
                                               @"Someone could be eavesdropping on you right now (man-in-the-middle attack)!\n"
                                               @"It is also possible that a host key has just been changed.\nConnect anyway?",
                     session.host, fingerprint];
                break;
                
            case NMSSHKnownHostStatusNotFound:
                message =
                    [NSString stringWithFormat:@"The authenticity of host '%@' can't be established.\n"
                                               @"DSA key fingerprint is %@.\nConnect anyay?",
                        session.host, fingerprint];
                _okToAdd = YES;
                break;
        }
        if (message) {
            result = [[FileTransferManager sharedInstance] transferrableFile:self
                                                              confirmMessage:message];
        }
    });
    return result;
}

- (NSString *)session:(NMSSHSession *)session keyboardInteractiveRequest:(NSString *)request {
    __block NSString *string;
    dispatch_sync(dispatch_get_main_queue(), ^() {
        string = [[FileTransferManager sharedInstance] transferrableFile:self
                                               keyboardInteractivePrompt:request];
    });
    return string;
}

@end
