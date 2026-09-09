//
//  SCPFile.m
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "SCPFile.h"
#import "iTermUserDefaults.h"
#import <NMSSH/NMSSH.h>
#import <NMSSH/NMSSHConfig.h>
#import <NMSSH/NMSSHHostConfig.h>
#import <NMSSH/libssh2.h>
#include <errno.h>

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSWorkspace+iTerm.h"
#import "ProfileModel.h"
#import "iTermOpenDirectory+MainApp.h"
#import "iTermSSHHelpers.h"
#import "iTermSlowOperationGateway.h"
#import "iTermWarning.h"

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
    NSString *_tempArchivePath;  // Path to temp tgz file when uploading a directory
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
    return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.DisplayName", nil, [NSBundle mainBundle], @"Secure copy\nUser name: %1$@\nHost: %2$@\nFile: %3$@", @"Display name for an SCP transfer; first %@ is the user name, second %@ is the host, third %@ is the file path"), _path.username, _path.hostname, _path.path];
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
    return NSLocalizedStringWithDefaultValue(@"SCPFile.ProtocolName", nil, [NSBundle mainBundle], @"secure copy", @"Name of the secure copy (SCP) transfer protocol");
}

// This runs in a thread.
- (void)performTransferWrapper:(BOOL)isDownload {
    [self performTransfer:isDownload];
    if (self.session && self.session.isConnected) {
        [self.session disconnect];
    }
    self.session = nil;

    // Clean up temp archive if we created one for a directory upload
    if (_tempArchivePath) {
        DLog(@"Cleaning up temp archive: %@", _tempArchivePath);
        [[NSFileManager defaultManager] removeItemAtPath:_tempArchivePath error:nil];
        _tempArchivePath = nil;
    }
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
        if (!privateKey) {
            return NO;  // Can't read file; auth will fail anyway
        }

        // Traditional PEM format: check for ENCRYPTED header
        if ([privateKey rangeOfString:@"ENCRYPTED"].location != NSNotFound) {
            return YES;
        }

        // OpenSSH new format: parse the cipher field
        NSString *beginMarker = @"-----BEGIN OPENSSH PRIVATE KEY-----";
        NSString *endMarker = @"-----END OPENSSH PRIVATE KEY-----";
        NSRange beginRange = [privateKey rangeOfString:beginMarker];
        if (beginRange.location == NSNotFound) {
            return NO;  // Unknown format, assume unencrypted
        }

        NSRange endRange = [privateKey rangeOfString:endMarker];
        if (endRange.location == NSNotFound) {
            return NO;
        }

        // Extract and decode base64 content
        NSUInteger start = NSMaxRange(beginRange);
        NSString *b64 = [privateKey substringWithRange:NSMakeRange(start, endRange.location - start)];
        b64 = [[b64 componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
               componentsJoinedByString:@""];

        NSData *decoded = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
        if (!decoded || decoded.length < 20) {
            return NO;
        }

        const char *bytes = decoded.bytes;

        // Verify AUTH_MAGIC: "openssh-key-v1" + null byte (15 bytes total)
        if (strncmp(bytes, "openssh-key-v1", 14) != 0 || bytes[14] != '\0') {
            return NO;
        }

        // Read cipher name (length-prefixed string at offset 15)
        NSUInteger offset = 15;
        if (offset + 4 > decoded.length) {
            return NO;
        }

        // Length is 4 bytes big-endian
        uint32_t cipherLen = ((uint32_t)(uint8_t)bytes[offset] << 24) |
                             ((uint32_t)(uint8_t)bytes[offset + 1] << 16) |
                             ((uint32_t)(uint8_t)bytes[offset + 2] << 8) |
                             ((uint32_t)(uint8_t)bytes[offset + 3]);
        offset += 4;

        if (offset + cipherLen > decoded.length) {
            return NO;
        }

        // If cipher is "none", key is unencrypted
        if (cipherLen == 4 && strncmp(bytes + offset, "none", 4) == 0) {
            return NO;
        }

        return YES;  // Encrypted with some cipher
    }
}


// This runs in a thread
+ (NSArray<NMSSHConfig *> *)configs {
    return [iTermSSHHelpers configs];
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
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gNMSSHTraceCallback = ^(NSData *data) {
            DLog(@"libssh2 trace: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        };
    });
    NSString *baseName = [[self class] fileNameForPath:self.path.path];
    RLog(@"performTransfer download=%@ agentAllowed=%@ path=%@ baseName=%@",
         @(isDownload), @(agentAllowed), self.path, baseName);
    if (!baseName) {
        self.error = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.InvalidPath", nil, [NSBundle mainBundle], @"Invalid path: %@", @"Error shown when the remote path is invalid; %@ is the path"), self.path.path];
        [self performOnMainThread:^{
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:SCPFileError(NSLocalizedStringWithDefaultValue(@"SCPFile.InvalidFilename", nil, [NSBundle mainBundle], @"Invalid filename", @"Error shown when the remote path has no valid filename component"))];
        }];
        return;
    }
    _okToAdd = NO;
    int effectivePort;
    if (self.session) {
        self.session.delegate = self;
        effectivePort = self.session.port.intValue;
    } else {
        RLog(@"Create seession to hostname=%@ configs=%@ port=%@ username=%@",
             [self hostname], [SCPFile configs], @([self port]), self.path.username);
        self.session = [[NMSSHSession alloc] initWithHost:[self hostname]
                                                  configs:[SCPFile configs]
                                          withDefaultPort:[self port]
                                          defaultUsername:self.path.username];
        effectivePort = self.session.port.intValue;
        self.session.delegate = self;
        [self.session connect];
        if (self.stopped) {
            XLog(@"Stop after connect");
            [self performOnMainThread:^{
                [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
            }];
            return;
        }
    }
    NSURL *url = [self sessionURL];
    if (!self.session.isConnected) {
        RLog(@"Not connected");
        NSError *theError = [self lastError];
        if (!theError) {
            // If connection fails, there is no rawSession in NMSSHSession, so it can't return an
            // error. Should that ever change, this clause will not execute.
            theError = [NSError errorWithDomain:@"com.googlecode.iterm2"
                                           code:-1
                                       userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"SCPFile.CouldNotConnect", nil, [NSBundle mainBundle], @"Could not connect.", @"Error shown when a connection to a host could not be established") }];
        }
        self.error = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.ConnectionFailed", nil, [NSBundle mainBundle], @"Connection failed: %@", @"Error shown when connecting to a host fails; %@ is the underlying error"),
                         theError.localizedDescription];
        [self performOnMainThread:^{
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:theError];
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.FailedToConnect", nil, [NSBundle mainBundle], @"Failed to connect to %1$@:%2$d. Double-check that the host name is correct.", @"Warning shown when connecting to a host fails; %@ is the host name and %d is the port"), self.hostname, effectivePort]
                                           actions:@[ iTermLocalizedOK(), NSLocalizedStringWithDefaultValue(@"SCPFile.Help", nil, [NSBundle mainBundle], @"Help", @"Button that opens help documentation") ]
                                     actionMapping:nil
                                         accessory:nil
                                        identifier:kSecureCopyConnectionFailedWarning
                                       silenceable:kiTermWarningTypePermanentlySilenceable
                                           heading:NSLocalizedStringWithDefaultValue(@"SCPFile.ConnectionFailedHeading", nil, [NSBundle mainBundle], @"Connection Failed", @"Heading of the dialog shown when connecting to a host fails")
                                       cancelLabel:NSLocalizedStringWithDefaultValue(@"SCPFile.Help", nil, [NSBundle mainBundle], @"Help", @"Button that opens help documentation")
                                            window:nil];
            if (selection == kiTermWarningSelection1) {
                [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/troubleshoot-hostname"]
                                                   target:nil
                                                    style:iTermOpenStyleTab
                                                   window:nil];
            }
        }];
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
                NSString *password = [self keyboardInteractiveRequest:NSLocalizedStringWithDefaultValue(@"SCPFile.PasswordPrompt", nil, [NSBundle mainBundle], @"password", @"Prompt word shown when asking the user for a password")];
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
                    const BOOL keyIsEncrypted = [self privateKeyIsEncrypted:keyPath];
                    NSString *password = nil;
                    BOOL firstAttempt = YES;

                    // Loop to allow retry on wrong passphrase
                    while (!self.stopped && self.session.session) {
                        if (keyIsEncrypted) {
                            NSString *prompt;
                            if (firstAttempt) {
                                prompt = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.PassphrasePrompt", nil, [NSBundle mainBundle], @"passphrase for private key “%@”:", @"Prompt asking for the passphrase of a private key; %@ is the key file path"),
                                          keyPath];
                            } else {
                                prompt = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.CorrectPassphrasePrompt", nil, [NSBundle mainBundle], @"correct passphrase for “%@”:", @"Prompt asking again for the passphrase of a private key after a wrong attempt; %@ is the key file path"),
                                          keyPath];
                            }
                            password = [self keyboardInteractiveRequest:prompt];
                            if (!password) {
                                self.stopped = YES;
                                break;
                            }
                            firstAttempt = NO;
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

                        // If key is not encrypted, don't retry - the key itself wasn't accepted
                        if (!keyIsEncrypted) {
                            break;
                        }
                        // For encrypted keys, loop back to ask for passphrase again
                        XLog(@"Wrong passphrase for %@, prompting again", keyPath);
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
        [self performOnMainThread:^{
            [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
        }];
        return;
    }
    if (!self.session.session && didConnectToAgent) {
        RLog(@"Retry without agent");
        // Try again without agent. I got into a state where using the agent prevented connections
        // from going through.
        [self.session disconnect];
        self.session = nil;
        [self performTransfer:isDownload agentAllowed:NO];
        return;
    }
    if (!self.session.isAuthorized) {
        RLog(@"Still not authenticated.");
        __block NSError *error = [self lastError];
        [self performOnMainThread:^{
            if (!error) {
                error = [NSError errorWithDomain:@"com.googlecode.iterm2.SCPFile"
                                            code:0
                                        userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedStringWithDefaultValue(@"SCPFile.AuthenticationFailed", nil, [NSBundle mainBundle], @"Authentication failed.", @"Error shown when SSH authentication fails") }];
            }
            self.error = NSLocalizedStringWithDefaultValue(@"SCPFile.AuthenticationError", nil, [NSBundle mainBundle], @"Authentication error.", @"Error shown when SSH authentication fails");
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        }];
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
            self.error = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.DownloadsNotWritable", nil, [NSBundle mainBundle], @"Downloads folder not writable. Tried %@", @"Error shown when the Downloads folder is not writable; %@ is the path that was tried"),
                          downloadDirectory];
            [self performOnMainThread:^{
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(NSLocalizedStringWithDefaultValue(@"SCPFile.DownloadsNotWritableShort", nil, [NSBundle mainBundle], @"Downloads folder not writable", @"Error shown when the Downloads folder is not writable"))];
            }];
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
            [self performOnMainThread:^{
                if (!self.stopped) {
                    [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
                }
            }];
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
            RLog(@"Download OK");
            error = nil;
            // We determine the filename and perform the move in the main thread to avoid two
            // threads trying to determine the final destination at the same time.
            [self performOnMainThread:^{
                finalDestination = [self finalDestinationForPath:baseName
                                            destinationDirectory:downloadDirectory
                                                          prompt:YES];
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
            }];
            if (error) {
                self.error = error.localizedDescription;
                RLog(@"%@", error);
            }
            [[NSFileManager defaultManager] removeItemAtPath:tempfile error:NULL];
            self.destination = finalDestination;
        } else {
            RLog(@"Download failed.");
            const BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:tempfile error:&error];
            DLog(@"Remove %@: %@", tempfile, error);
            if (quarantineError && (!ok || error)) {
                [self performOnMainThread:^{
                    [self failedToRemoveUnquarantinedFileAt:tempfile];
                }];
            }
            if (self.stopped) {
                [self performOnMainThread:^{
                    [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
                }];
                return;
            } else {
                if (quarantineError) {
                    self.error = NSLocalizedStringWithDefaultValue(@"SCPFile.QuarantineError", nil, [NSBundle mainBundle], @"Quarantine Error", @"Error shown when a downloaded file could not be marked as quarantined");
                } else {
                    NSString *errorDescription = [[self lastError] localizedDescription];
                    if (errorDescription.length) {
                        self.error = errorDescription;
                    } else {
                        self.error = NSLocalizedStringWithDefaultValue(@"SCPFile.DownloadFailed", nil, [NSBundle mainBundle], @"Download failed", @"Error shown when an SCP download fails");
                    }
                }
                error = SCPFileError(NSLocalizedStringWithDefaultValue(@"SCPFile.DownloadFailed", nil, [NSBundle mainBundle], @"Download failed", @"Error shown when an SCP download fails"));
            }
        }
        [self performOnMainThread:^{
            if (!error) {
                self.localPath = finalDestination;
            }
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        }];
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
        RLog(@"Upload “%@” to “%@”", [self localPath], self.path.path);
        BOOL ok = [self.session.channel uploadFile:[self localPath]
                                                to:self.path.path
                                          progress:^BOOL (NSUInteger bytes) {
            self.bytesTransferred = bytes;
            [self performOnMainThread:^{
                                                  if (!self.stopped) {
                                                      [[FileTransferManager sharedInstance] transferrableFileProgressDidChange:self];
                                                  }
            }];
            return !self.stopped;
        }];
        NSError *error;
        if (ok) {
            RLog(@"Upload OK");
            error = nil;
        } else {
            RLog(@"Upload failed: %@", error);
            if (self.stopped) {
                [self performOnMainThread:^{
                    [[FileTransferManager sharedInstance] transferrableFileDidStopTransfer:self];
                }];
                return;
            } else {
                NSString *errorDescription = [[self lastError] localizedDescription];
                if (errorDescription.length) {
                    self.error = errorDescription;
                } else {
                    self.error = NSLocalizedStringWithDefaultValue(@"SCPFile.UploadFailed", nil, [NSBundle mainBundle], @"Upload failed", @"Error shown when an SCP upload fails");
                }
                error = SCPFileError(NSLocalizedStringWithDefaultValue(@"SCPFile.UploadFailed", nil, [NSBundle mainBundle], @"Upload failed", @"Error shown when an SCP upload fails"));
            }
        }
        [self performOnMainThread:^{
            [[FileTransferManager sharedInstance] transferrableFile:self
                                     didFinishTransmissionWithError:error];
        }];
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

- (void)performOnMainThread:(void (^ NS_NOESCAPE)(void))block {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    dispatch_async(dispatch_get_main_queue(), ^() {
        [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            block();
            dispatch_group_leave(group);
        }];
    });
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

- (NSString *)tempFileName {
    NSString *result = [NSString stringWithFormat:@".iTerm2.%@", [NSString uuid]];

    return result;
}

static NSString *const SCPFileKnownHostsUserDefaultsKey = @"NoSyncKnownHosts";

- (NSString *)userHostPort {
    return [NSString stringWithFormat:@"%@@%@:%@", self.path.username, self.hostname, @(self.port)];
}

- (BOOL)hostnameIsKnown {
    return [[[iTermUserDefaults userDefaults] objectForKey:SCPFileKnownHostsUserDefaultsKey] containsObject:self.userHostPort];
}

- (BOOL)shouldConnectToNewHostname {
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.ConnectToPrompt", nil, [NSBundle mainBundle], @"Connect to %@?", @"Title of the dialog asking whether to connect to a host; %@ is user@host:port"), self.userHostPort]
                               actions:@[ iTermLocalizedOK(), iTermLocalizedCancel() ]
                             accessory:nil
                            identifier:[@"NoSyncConnectTo_" stringByAppendingString:self.userHostPort]
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:NSLocalizedStringWithDefaultValue(@"SCPFile.ConnectToNewHostHeading", nil, [NSBundle mainBundle], @"Connect to New Host?", @"Heading of the dialog asking whether to connect to a previously unknown host")
                                window:nil];
    return selection == kiTermWarningSelection0;
}

- (void)addKnownHost {
    NSArray<NSString *> *hosts = [[iTermUserDefaults userDefaults] objectForKey:SCPFileKnownHostsUserDefaultsKey] ?: @[];
    hosts = [hosts arrayByAddingObject:self.userHostPort];
    [[iTermUserDefaults userDefaults] setObject:hosts forKey:SCPFileKnownHostsUserDefaultsKey];
}

- (void)download {
    _downloading = YES;
    self.status = kTransferrableFileStatusStarting;
    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];

    if (!self.hasPredecessor) {
        if (![self hostnameIsKnown]) {
            if (![self shouldConnectToNewHostname]) {
                self.error = NSLocalizedStringWithDefaultValue(@"SCPFile.CanceledByUser", nil, [NSBundle mainBundle], @"Canceled by user", @"Error shown when the user cancels an SCP transfer");
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(NSLocalizedStringWithDefaultValue(@"SCPFile.CanceledByUser", nil, [NSBundle mainBundle], @"Canceled by user", @"Error shown when the user cancels an SCP transfer"))];
                return;
            }
            [self addKnownHost];
        }
        dispatch_async(_queue, ^() {
            [self performTransferWrapper:YES];
        });
    }
}

// If localPath is a directory, creates a tgz archive and updates localPath and path.path.
// Returns the file attributes on success, or nil on failure (after reporting the error).
- (NSDictionary *)archiveDirectoryIfNeededWithAttributes:(NSDictionary *)attrs {
    NSString *fileType = attrs[NSFileType];
    if (![fileType isEqualToString:NSFileTypeDirectory]) {
        return attrs;
    }

    DLog(@"Uploading directory as tgz: %@", self.localPath);

    NSError *error = nil;
    _tempArchivePath = [NSData temporaryTGZArchiveOfDirectory:self.localPath error:&error];
    if (!_tempArchivePath) {
        self.error = error.localizedDescription;
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:error];
        return nil;
    }

    // Update paths to use the archive
    self.localPath = _tempArchivePath;
    self.path.path = [self.path.path stringByAppendingString:@".tgz"];

    // Return updated attrs for the new file
    return [[NSFileManager defaultManager] attributesOfItemAtPath:self.localPath error:nil];
}

- (void)upload {
    _downloading = NO;
    self.status = kTransferrableFileStatusStarting;

    // Verify the file exists and is readable before starting the upload
    NSError *attributesError = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.localPath error:&attributesError];
    if (attributesError) {
        RLog(@"Failed to get attributes for %@: %@", self.localPath, attributesError);
        self.error = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.CannotReadFile", nil, [NSBundle mainBundle], @"Cannot read file: %@", @"Error shown when a file to upload cannot be read; %@ is the underlying error"), attributesError.localizedDescription];
        [[FileTransferManager sharedInstance] transferrableFile:self
                                 didFinishTransmissionWithError:attributesError];
        return;
    }

    // If it's a directory, create a tgz archive
    attrs = [self archiveDirectoryIfNeededWithAttributes:attrs];
    if (!attrs) {
        return;
    }

    self.fileSize = [attrs fileSize];
    DLog(@"upload: localPath=%@ fileSize=%@", self.localPath, @(self.fileSize));

    [[[FileTransferManager sharedInstance] files] addObject:self];
    [[FileTransferManager sharedInstance] transferrableFileDidStartTransfer:self];

    if (!self.hasPredecessor) {
        if (![self hostnameIsKnown]) {
            if (![self shouldConnectToNewHostname]) {
                self.error = NSLocalizedStringWithDefaultValue(@"SCPFile.CanceledByUser", nil, [NSBundle mainBundle], @"Canceled by user", @"Error shown when the user cancels an SCP transfer");
                [[FileTransferManager sharedInstance] transferrableFile:self
                                         didFinishTransmissionWithError:SCPFileError(NSLocalizedStringWithDefaultValue(@"SCPFile.CanceledByUser", nil, [NSBundle mainBundle], @"Canceled by user", @"Error shown when the user cancels an SCP transfer"))];
                return;
            }
            [self addKnownHost];
        }
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
    const NMSSHKnownHostStatus status = [self.session knownHostStatusInFiles:nil];
    NSString *host = session.host;
    NSString *hashName = @"";
    switch (session.fingerprintHash) {
        case NMSSHSessionHashMD5:
            hashName = @"MD5";
            break;
        case NMSSHSessionHashSHA1:
            hashName = @"SHA1";
            break;
    }
    [self performOnMainThread:^{
        _okToAdd = NO;
        NSString *message = nil;
        // Localization unneeded
        NSString *title = @"Notice";  // The default value should never be used.
        switch (status) {
            case NMSSHKnownHostStatusFailure:
                title = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.ProblemConnecting", nil, [NSBundle mainBundle], @"Problem connecting to %@", @"Title shown when there is a problem connecting to a host; %@ is the host"), host];
                message = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.KnownHostsUnreadable", nil, [NSBundle mainBundle], @"Could not read the known_hosts file.\n"
                                                     @"As a result, the authenticity of host '%1$@' can't be established."
                                                     @"%2$@ key fingerprint is %3$@. Connect anyway?", @"Warning shown when the known_hosts file cannot be read; first %@ is the host, second %@ is the key hash type, third %@ is the fingerprint"),
                           host, hashName, fingerprint];
                break;

            case NMSSHKnownHostStatusMatch:
                result = YES;
                message = nil;
                break;

            case NMSSHKnownHostStatusMismatch:
                title = NSLocalizedStringWithDefaultValue(@"SCPFile.WarningTitle", nil, [NSBundle mainBundle], @"Warning!", @"Title of a warning dialog shown when a host key has changed");
                message =
                    [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.HostIdentificationChanged", nil, [NSBundle mainBundle], @"REMOTE HOST IDENTIFICATION HAS CHANGED!\n\n"
                                               @"The %1$@ key fingerprint of host '%2$@' has changed. It is %3$@.\n\n"
                                               @"Someone could be eavesdropping on you right now (man-in-the-middle attack)!\n"
                                               @"It is also possible that a host key has just been changed.\nConnect anyway?", @"Warning shown when a host's key fingerprint has changed; first %@ is the key hash type, second %@ is the host, third %@ is the fingerprint"),
                     hashName, self.hostname, fingerprint];
                break;

            case NMSSHKnownHostStatusNotFound:
                title = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.FirstTimeConnecting", nil, [NSBundle mainBundle], @"First time connecting to %@", @"Title shown when connecting to a host for the first time; %@ is the host"), host];
                message =
                    [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"SCPFile.AuthenticityUnknown", nil, [NSBundle mainBundle], @"The authenticity of host '%1$@' can't be established.\n\n"
                                               @"%2$@ key fingerprint is %3$@.\n\nConnect anyway?", @"Prompt shown when connecting to a host for the first time; first %@ is the host, second %@ is the key hash type, third %@ is the fingerprint"),
                     host, hashName, fingerprint];
                _okToAdd = YES;
                break;
        }
        if (message) {
            result = [[FileTransferManager sharedInstance] transferrableFile:self
                                                                       title:title
                                                              confirmMessage:message];
        }
    }];
    return result;
}

- (NSString *)session:(NMSSHSession *)session keyboardInteractiveRequest:(NSString *)request {
    __block NSString *string;
    [self performOnMainThread:^{
        string = [self keyboardInteractiveRequest:request];
    }];
    return string;
}

@end
