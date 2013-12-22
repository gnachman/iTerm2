//
//  SCPFile.m
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "SCPFile.h"
#import "NMSSH.framework/Headers/NMSSH.h"
#import "NMSSH.framework/Headers/libssh2.h"
#import "NSObject+iTerm.h"

static NSString *const kPublicKeyPath = @"~/.ssh/id_rsa.pub";
static NSString *const kPrivateKeyPath = @"~/.ssh/id_rsa";

static NSString *const kSCPFileErrorDomain = @"com.googlecode.iterm2.SCPFile";

static NSError *SCPFileError(NSString *description) {
    return [NSError errorWithDomain:kSCPFileErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}

@interface SCPFile () <NMSSHSessionDelegate>
@property(atomic, assign) NMSSHSession *session;
@property(atomic, assign) BOOL stopped;
@end

@implementation SCPFile {
    dispatch_queue_t _queue;
}

- (id)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.googlecode.iterm2.SCPFile", NULL);
    }
    return self;
}

- (NSString *)displayName {
    return [NSString stringWithFormat:@"scp %@@%@:%@", _path.username, _path.hostname, _path.path];
}

+ (NSString *)fileNameForPath:(NSString *)path {
    NSArray *components = [path pathComponents];
    if (!components.count) {
        return nil;
    }
    return [components lastObject];
}

- (BOOL)havePrivateKey {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:[kPrivateKeyPath stringByExpandingTildeInPath]];
}

// This runs in a thread.
- (void)performTransfer:(BOOL)isDownload {
    NSString *baseName = [[self class] fileNameForPath:self.path.path];
    if (!baseName) {
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:SCPFileError(@"Invalid filename")];
        });
        return;
    }
    self.session = [[[NMSSHSession alloc] initWithHost:self.path.hostname
                                           andUsername:self.path.username] autorelease];
    self.session.delegate = self;
    [self.session connect];
    if (self.stopped) {
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
        });
        return;
    }
    
    if (!self.session.isConnected) {
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:self.session.lastError];
        });
        return;
    }
    
    NSArray *authTypes = [self.session supportedAuthenticationMethods];
    if (!authTypes) {
        authTypes = @[ @"password" ];
    }
    for (NSString *authType in authTypes) {
        if (self.stopped) {
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
        } else if ([authType isEqualToString:@"publickey"] && [self havePrivateKey]) {
            __block NSString *password;
            dispatch_sync(dispatch_get_main_queue(), ^() {
                password = [[FileTransferManager sharedInstance] transferrableFile:self
                                                         keyboardInteractivePrompt:@"Password for private key:"];
            });
            if (self.stopped) {
                break;
            }
            [self.session authenticateByPublicKey:[kPublicKeyPath stringByExpandingTildeInPath]
                                       privateKey:[kPrivateKeyPath stringByExpandingTildeInPath]
                                      andPassword:password];
            if (self.session.isAuthorized) {
                break;
            }
        }
    }

    if (self.stopped) {
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
        });
        return;
    }
    if (!self.session.isAuthorized) {
        dispatch_sync(dispatch_get_main_queue(), ^() {
            NSError *error = self.session.lastError;
            if (!error) {
                error = [NSError errorWithDomain:@"com.googlecode.iterm2.SCPFile"
                                            code:0
                                        userInfo:@{ NSLocalizedDescriptionKey: @"Authentication failed." }];
            }
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        });
        return;
    }
    
    if (isDownload) {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory,
                                                             NSUserDomainMask,
                                                             YES);
        NSString *tempfile = nil;
        NSString *finalDestination = nil;
        NSString *uuid = [self uuid];
        NSString *name = baseName;
        int retries = 0;
        for (NSString *path in paths) {
            if ([[NSFileManager defaultManager] isWritableFileAtPath:path]) {
                tempfile = [path stringByAppendingPathComponent:uuid];
                do {
                    finalDestination = [path stringByAppendingPathComponent:name];
                    ++retries;
                    NSRange rangeOfDot = [baseName rangeOfString:@"."];
                    NSString *prefix = baseName;
                    NSString *suffix = @"";
                    if (rangeOfDot.length > 0) {
                        prefix = [baseName substringToIndex:rangeOfDot.location];
                        suffix = [baseName substringFromIndex:rangeOfDot.location];
                    }
                    name = [NSString stringWithFormat:@"%@ (%d)%@", prefix, retries, suffix];
                } while ([[NSFileManager defaultManager] fileExistsAtPath:finalDestination]);
                break;
            }
        }
        if (!tempfile) {
            dispatch_sync(dispatch_get_main_queue(), ^() {
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(@"Downloads folder not writable")];
            });
            return;
        }
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
                                                return !self.stopped;
                                            }];
        NSError *error;
        if (ok) {
            error = nil;
            [[NSFileManager defaultManager] moveItemAtPath:tempfile
                                                    toPath:finalDestination
                                                     error:&error];
        } else {
            error = SCPFileError(@"Download failed");
        }
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        });
    } else {
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
            error = SCPFileError(@"Upload failed");
        }
        dispatch_sync(dispatch_get_main_queue(), ^() {
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        });
    }
}

- (NSString *)uuid {
    CFUUIDRef   uuid;
    CFStringRef uuidStr;
    
    uuid = CFUUIDCreate(NULL);
    uuidStr = CFUUIDCreateString(NULL, uuid);
    
    NSString *result = [[(NSString *)uuidStr copy] autorelease];

    CFRelease(uuidStr);
    CFRelease(uuid);
    
    return result;
}

- (void)download {
    self.status = kTransferrableFileStatusStarting;
    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];

    dispatch_async(_queue, ^() {
        [self performTransfer:YES];
    });
}

- (void)upload {
    self.status = kTransferrableFileStatusStarting;
    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];
    
    dispatch_async(_queue, ^() {
        [self performTransfer:NO];
    });
}

- (void)stop {
    self.stopped = YES;
}

- (BOOL)session:(NMSSHSession *)session shouldConnectToHostWithFingerprint:(NSString *)fingerprint {
    __block BOOL result;
    dispatch_sync(dispatch_get_main_queue(), ^(void) {
        BOOL known;
        BOOL okToAdd = NO;
        NSString *message;
        switch ([self.session knownHostStatusFoFingerprint:fingerprint]) {
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
                okToAdd = YES;
                break;
        }
        if (message) {
            result = [[FileTransferManager sharedInstance] transferrableFile:self
                                                              confirmMessage:message];
        }
        if (okToAdd && result) {
            [session addCurrentHostToKnownHosts];
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
