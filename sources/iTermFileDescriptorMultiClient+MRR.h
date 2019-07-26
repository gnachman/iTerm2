//
//  iTermFileDescriptorMultiClient+MRR.h
//  iTerm2
//
//  Created by George Nachman on 8/9/19.
//

#import "iTermFileDescriptorMultiClient.h"
#import "iTermPosixTTYReplacements.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermFileDescriptorMultiClientAttachStatus) {
    iTermFileDescriptorMultiClientAttachStatusSuccess,
    iTermFileDescriptorMultiClientAttachStatusConnectFailed,
    iTermFileDescriptorMultiClientAttachStatusFatalError  // includes rejection, unexpected errors
};

iTermFileDescriptorMultiClientAttachStatus iTermConnectToUnixDomainSocket(const char *path, int *fdOut);
int iTermCreateConnectedUnixDomainSocket(const char *path,
                                         int closeAfterAccept,
                                         int *listenFDOut,
                                         int *acceptedFDOut,
                                         int *connectFDOut);

@interface iTermFileDescriptorMultiClient (Private)
- (iTermFileDescriptorMultiClientAttachStatus)tryAttach;
@end

@interface iTermFileDescriptorMultiClient (MRR)

- (iTermForkState)launchWithSocketPath:(NSString *)path
                            executable:(NSString *)executable;

@end

NS_ASSUME_NONNULL_END
