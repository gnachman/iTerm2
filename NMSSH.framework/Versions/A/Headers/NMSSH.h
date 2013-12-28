#import "libssh2.h"
#import "libssh2_sftp.h"

#import <CoreFoundation/CoreFoundation.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <arpa/inet.h>

#define kNMSSHBufferSize (0x4000)

@class NMSSHSession, NMSSHChannel, NMSFTP;

#import "NMSSHSession.h"
#import "NMSSHChannel.h"
#import "NMSFTP.h"

#import "NMSSHLogger.h"