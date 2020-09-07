//
//  iTermFileDescriptorMultiClient+MRR.h
//  iTerm2
//
//  Created by George Nachman on 8/9/19.
//

#import "iTermFileDescriptorMultiClient.h"

#import "iTermFileDescriptorMultiClientPendingLaunch.h"
#import "iTermPosixTTYReplacements.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermFileDescriptorMultiClientAttachStatus) {
    iTermFileDescriptorMultiClientAttachStatusSuccess,
    iTermFileDescriptorMultiClientAttachStatusConnectFailed,
    iTermFileDescriptorMultiClientAttachStatusFatalError,  // includes rejection, unexpected errors
    iTermFileDescriptorMultiClientAttachStatusInProgress  // connecting asynchronously
};

iTermFileDescriptorMultiClientAttachStatus iTermConnectToUnixDomainSocket(const char *path, int *fdOut, int async);

typedef struct {
    BOOL ok;
    // has called listen() on this one
    int listenFD;
    // has called accept() on this one
    int acceptedFD;
    // has called connect() on this one
    int connectedFD;
    // you can read() on this one. Valid only if ok=true
    int readFD;
} iTermUnixDomainSocketConnectResult;

iTermUnixDomainSocketConnectResult iTermCreateConnectedUnixDomainSocket(const char *path,
                                                                        int closeAfterAccept);

@interface iTermFileDescriptorMultiClient (MRR)

- (iTermForkState)launchWithSocketPath:(NSString *)path
                            executable:(NSString *)executable
                                readFD:(int *)readFDOut
                               writeFD:(int *)writeFDOut;
@end

NS_ASSUME_NONNULL_END
