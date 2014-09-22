#import "NMSSH.h"

/**
 NMSSHHostConfig describes a single host's configuration.
 */
@interface NMSSHHostConfig : NSObject

/**
 Patterns specified in the config file.
 */
@property(nonatomic, strong) NSArray *hostPatterns;

/**
 Specifies the real host name to log into. If the hostname contains the
 character sequence `%h', then the client should replace this with the
 user-specified host name (this is useful for manipulating unqualified names).
 This may be an IP address.
 */
@property(nonatomic, strong) NSString *hostname;

/**
 Specifies the user name to log in as.
 */
@property(nonatomic, strong) NSString *user;

/**
 Specifies the port number to connect on the remote host.
 */
@property(nonatomic, strong) NSNumber *port;

/**
 Specifies alist of file names from which the user's DSA, ECDSA or RSA
 authentication identity are read. It is empty by default. Tildes will be
 expanded to the user's home directory. The client should perform the following
 substitutions on each file name:
   "%d" should be replaced with the local user home directory
   "%u" should be replaced with the local user name
   "%l" should be replaced with the local host name
   "%h" should be replaced with the remote host name
   "%r" should be replaced with the remote user name
 If multiple identities are provided, the client should try them in order.
 */
@property(nonatomic, strong) NSArray *identityFiles;

/**
 Values for {other} are copied to {self} if not already set. Arrays are
 appended from {other} without adding duplicates.
 */
- (void)mergeFrom:(NMSSHHostConfig *)other;

@end
