#import "NMSSH.h"

@class NMSSHSession;

/**
 Protocol for registering to receive messages from an active NMSSHSession.
 */
@protocol NMSSHSessionDelegate <NSObject>
@optional

/**
 Called when the session is setup to use keyboard interactive authentication,
 and the server is sending back a question (e.g. a password request).

 @param session The session that is asking
 @param request Question from server
 @returns A valid response to the given question
 */
- (NSString *)session:(NMSSHSession *)session keyboardInteractiveRequest:(NSString *)request;

/**
 Called when a session has failed and disconnected.

 @param session The session that was disconnected
 @param error A description of the error that caused the disconnect
 */
- (void)session:(NMSSHSession *)session didDisconnectWithError:(NSError *)error;

/**
 Called when a session is connecting to a host, the fingerprint is used
 to verify the authenticity of the host.

 @param session The session that is connecting
 @param fingerprint The host's fingerprint
 @returns YES if the session should trust the host, otherwise NO.
 */
- (BOOL)session:(NMSSHSession *)session shouldConnectToHostWithFingerprint:(NSString *)fingerprint;

@end
