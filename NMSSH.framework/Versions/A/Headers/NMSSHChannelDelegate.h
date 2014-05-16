#import "NMSSH.h"

/**
 Protocol for registering to receive messages from an active NMSSHChannel.
 */
@protocol NMSSHChannelDelegate <NSObject>

@optional

/**
 Called when a channel read new data on the socket.

 @param channel The channel that read the message
 @param message The message that the channel has read
 */
- (void)channel:(NMSSHChannel *)channel didReadData:(NSString *)message;

/**
 Called when a channel read new error on the socket.

 @param channel The channel that read the error
 @param error The error that the channel has read
 */
- (void)channel:(NMSSHChannel *)channel didReadError:(NSString *)error;

/**
 Called when a channel read new data on the socket.

 @param channel The channel that read the message
 @param data The bytes that the channel has read
 */
- (void)channel:(NMSSHChannel *)channel didReadRawData:(NSData *)data;

/**
 Called when a channel read new error on the socket.

 @param channel The channel that read the error
 @param error The error that the channel has read
 */
- (void)channel:(NMSSHChannel *)channel didReadRawError:(NSData *)error;

/**
 Called when a channel in shell mode has been closed.

 @param channel The channel that has been closed
 */
- (void)channelShellDidClose:(NMSSHChannel *)channel;

@end
