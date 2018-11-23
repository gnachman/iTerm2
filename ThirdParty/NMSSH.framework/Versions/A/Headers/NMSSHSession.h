#import "NMSSH.h"

@class NMSSHHostConfig, NMSFTP;
@protocol NMSSHSessionDelegate;

typedef NS_ENUM(NSInteger, NMSSHSessionHash) {
    NMSSHSessionHashMD5,
    NMSSHSessionHashSHA1
};

typedef NS_ENUM(NSInteger, NMSSHKnownHostStatus) {
    NMSSHKnownHostStatusMatch,
    NMSSHKnownHostStatusMismatch,
    NMSSHKnownHostStatusNotFound,
    NMSSHKnownHostStatusFailure
};

/**
 NMSSHSession provides the functionality required to setup a SSH connection
 and authorize against it.

 In its simplest form it works like this:

    NMSSHSession *session = [NMSSHSession connectToHost:@"127.0.0.1:22"
                                           withUsername:@"user"];

    if (session.isConnected) {
        NSLog(@"Successfully created a new session");
    }

    [session authenticateByPassword:@"pass"];

    if (session.isAuthorized) {
        NSLog(@"Successfully authorized");
    }

 ## Thread safety

 NMSSH classes are not thread safe, you should use them from the same thread
 where you created the NMSSHSession instance.

 If you want to use multiple NMSSHSession instances at once you should implement
 the [crypto mutex callbacks](http://trac.libssh2.org/wiki/MultiThreading).
 */
@interface NMSSHSession : NSObject

/// ----------------------------------------------------------------------------
/// @name Setting the Delegate
/// ----------------------------------------------------------------------------

/**
 The receiver’s `delegate`.

 The `delegate` is sent messages when content is loading.
 */
@property (nonatomic, nullable, weak) id<NMSSHSessionDelegate> delegate;

/**
 The synthesized config for the current host, produced by combining values from
 all configs in the chain by priority, plus client-provided defaults. This is
 only set if NMSSHSession was initialized with a config chain.
 */
@property (nonatomic, nullable, readonly) NMSSHHostConfig *hostConfig;

/// ----------------------------------------------------------------------------
/// @name Initialize a new SSH session
/// ----------------------------------------------------------------------------

- (nonnull instancetype)init NS_UNAVAILABLE;

/**
 Shorthand method for initializing a NMSSHSession object and calling connect.

 @param host The server hostname (a port number can be specified by appending
             `@":{port}"`; for IPv6 addresses with a port, use
             `@"[{host}]:{port}"`.
 @param username A valid username the server will accept
 @returns NMSSHSession instance
 */
+ (nonnull instancetype)connectToHost:(nonnull NSString *)host withUsername:(nonnull NSString *)username;

/**
 Shorthand method for initializing a NMSSHSession object and calling connect,
 (explicitly setting a port number).

 @param host The server hostname
 @param port The port number
 @param username A valid username the server will accept
 @returns NMSSHSession instance
 */
+ (nonnull instancetype)connectToHost:(nonnull NSString *)host port:(NSInteger)port withUsername:(nonnull NSString *)username;

/**
 Create and setup a new NMSSH instance.

 @param host The server hostname (a port number can be specified by appending
             `@":{port}"`; for IPv6 addresses with a port, use
             `@"[{host}]:{port}"`.
 @param username A valid username the server will accept
 @returns NMSSHSession instance
 */
- (nonnull instancetype)initWithHost:(nonnull NSString *)host andUsername:(nonnull NSString *)username;

/**
 Create and setup a new NMSSH instance. This is the designated initializer.

 @param host The server hostname
 @param port The port number
 @param username A valid username the server will accept
 @returns NMSSHSession instance
 */
- (nonnull instancetype)initWithHost:(nonnull NSString *)host port:(NSInteger)port andUsername:(nonnull NSString *)username NS_DESIGNATED_INITIALIZER;

/**
 Create and setup a new NMSSH instance using a chain of config files.

 The {host} is used to perform a lookup in NMSSHConfig objects in the
 {configs} array, which may alias the hostname and provide a port number or user
 name. All information relevant to {host} in {configs} will be combined into
 a single NMSSHHostConfig and saved in {self.hostConfig}. A config-
 provided value will override {host}, {defaultUsername} or {defaultPort}. If no
 match is found then {host} is used as the host name.

 @param host Host to search {configs} with. If no matching config specifies a
     hostname, then {host} is the server hostname.
 @param configs An array of NMSSHHostConfig objects ordered from highest to
     lowest priority
 @param defaultPort The port number (may be overridden by a config)
 @param defaultUsername A valid username the server will accept (may be
     overridden by a config)
 */
- (nonnull instancetype)initWithHost:(nonnull NSString *)host
                             configs:(nonnull NSArray *)configs
                     withDefaultPort:(NSInteger)defaultPort
                     defaultUsername:(nonnull NSString *)defaultUsername;

/// ----------------------------------------------------------------------------
/// @name Connection settings
/// ----------------------------------------------------------------------------

/** Full server hostname in the format `@"{hostname}"`. */
@property (nonatomic, nonnull, readonly) NSString *host;

/** The server port to connect to. */
@property (nonatomic, nonnull, readonly) NSNumber *port;

/** Username that will authenticate against the server. */
@property (nonatomic, nonnull, readonly) NSString *username;

/** Timeout for libssh2 blocking functions. */
@property (nonatomic, nonnull, strong) NSNumber *timeout;

/** Last session error. */
@property (nonatomic, nullable, readonly) NSError *lastError;

/** The hash algorithm to use to encode the fingerprint during connection, default value is NMSSHSessionHashMD5. */
@property (nonatomic, assign) NMSSHSessionHash fingerprintHash;

/** The banner that will be sent to the remote host when the SSH session is started. */
@property (nonatomic, nullable, strong) NSString *banner;

/** The remote host banner. */
@property (nonatomic, nullable, readonly) NSString *remoteBanner;

/// ----------------------------------------------------------------------------
/// @name Raw libssh2 session and socket reference
/// ----------------------------------------------------------------------------

/** Raw libssh2 session instance. */
@property (nonatomic, nullable, readonly, getter = rawSession) LIBSSH2_SESSION *session;

/** Raw session socket. */
@property (nonatomic, nullable, readonly) CFSocketRef socket;

/// ----------------------------------------------------------------------------
/// @name Open/Close a connection to the server
/// ----------------------------------------------------------------------------

/**
 A Boolean value indicating whether the session connected successfully
 (read-only).
 */
@property (nonatomic, readonly, getter = isConnected) BOOL connected;

/**
 Connect to the server using the default timeout (10 seconds)

 @returns Connection status
 */
- (BOOL)connect;

/**
 Connect to the server.

 @param timeout The time, in seconds, to wait before giving up.
 @returns Connection status
 */
- (BOOL)connectWithTimeout:(nonnull NSNumber *)timeout;

/**
 Close the session
 */
- (void)disconnect;

/// ----------------------------------------------------------------------------
/// @name Authentication
/// ----------------------------------------------------------------------------

/**
 A Boolean value indicating whether the session is successfully authorized
 (read-only).
 */
@property (nonatomic, readonly, getter = isAuthorized) BOOL authorized;

/**
 Authenticate by password

 @param password Password for connected user
 @returns Authentication success
 */
- (BOOL)authenticateByPassword:(nonnull NSString *)password;

/**
 Authenticate by private key pair from file(s)

 Use password:nil when the key is unencrypted

 @param publicKey Filepath to public key
 @param privateKey Filepath to private key
 @param password Password for encrypted private key
 @returns Authentication success
 */
- (BOOL)authenticateByPublicKey:(nullable NSString *)publicKey
                     privateKey:(nonnull NSString *)privateKey
                    andPassword:(nullable NSString *)password;

/**
 Authenticate by private key pair

 Use password:nil when the key is unencrypted

 @param publicKey public key
 @param privateKey private key
 @param password Password for encrypted private key
 @returns Authentication success
 */
- (BOOL)authenticateByInMemoryPublicKey:(nullable NSString *)publicKey
                             privateKey:(nonnull NSString *)privateKey
                            andPassword:(nullable NSString *)password;

/**
 Authenticate by keyboard-interactive using delegate.

 @returns Authentication success
 */
- (BOOL)authenticateByKeyboardInteractive;

/**
 Authenticate by keyboard-interactive using block.

 @param authenticationBlock The block to apply to server requests.
     The block takes one argument:

     _request_ - Question from server<br>
     The block returns a NSString object that represents a valid response
     to the given question.
 @returns Authentication success
 */
- (BOOL)authenticateByKeyboardInteractiveUsingBlock:(NSString * _Nonnull(^_Nullable)( NSString * _Nonnull request))authenticationBlock;

/**
 Setup and connect to an SSH agent

 @returns Authentication success
 */
- (BOOL)connectToAgent;

/**
 Get supported authentication methods

 @returns Array of string descripting supported authentication methods
 */
- (nullable NSArray<NSString *> *)supportedAuthenticationMethods;

/**
 Get the fingerprint of the remote host.
 The session must be connected to an host.

 @param hashType The hash algorithm to use to encode the fingerprint
 @returns The host's fingerprint
 */
- (nullable NSString *)fingerprint:(NMSSHSessionHash)hashType;

/// ----------------------------------------------------------------------------
/// @name Known hosts
/// ----------------------------------------------------------------------------

/**
 Checks if the hosts's key is recognized.

 The session must be connected. Each file is checked in order,
 returning as soon as the host is found.

 @warning In a sandboxed Mac app or iOS app, _files_ must not be `nil` as the default files are not accessible.

 @param files An array of filenames to check, or `nil` to use the default paths.
 @returns Known host status for current host.
 */
- (NMSSHKnownHostStatus)knownHostStatusInFiles:(nullable NSArray<NSString *> *)files;

/**
 Adds the passed-in host to the user's known hosts file.

 _hostName_ may be a numerical IP address or a full name. If it includes
 a port number, it should be formatted as `@"[{host}]:{port}"` (e.g., `@"[example.com]:2222"`).
 If _salt_ is set, then _hostName_ must contain a hostname salted and hashed with SHA1 and then base64-encoded.

 A simple example:

    [session addKnownHostName:session.host
                         port:[session.port intValue]
                       toFile:nil
                     withSalt:nil];

 @warning  On Mac OS, the default filename is `~/.ssh/known_hosts`, and will not be writable in a sandboxed environment.

 @param hostName The hostname or IP address to add.
 @param port The port number of the host to add.
 @param fileName The path to the known_hosts file, or `nil` for the default.
 @param salt The base64-encoded salt used for hashing. May be `nil`.
 @returns Success status.
 */
- (BOOL)addKnownHostName:(nonnull NSString *)hostName
                    port:(NSInteger)port
                  toFile:(nullable NSString *)fileName
                withSalt:(nullable NSString *)salt;

/// ----------------------------------------------------------------------------
/// @name Quick channel/sftp access
/// ----------------------------------------------------------------------------

/** Get a pre-configured NMSSHChannel object for the current session (read-only). */
@property (nonatomic, nonnull, readonly) NMSSHChannel *channel;

/** Get a pre-configured NMSFTP object for the current session (read-only). */
@property (nonatomic, nonnull, readonly) NMSFTP *sftp;

@end
