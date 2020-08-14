//
//  pidinfoProtocol.h
//  pidinfo
//
//  Created by George Nachman on 1/11/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol pidinfoProtocol

- (void)getProcessInfoForProcessID:(NSNumber *)pid
                            flavor:(NSNumber *)flavor
                               arg:(NSNumber *)arg
                              size:(NSNumber *)size
                             reqid:(int)reqid
                         withReply:(void (^ _Nonnull)(NSNumber *rc, NSData *buffer))reply;

- (void)handshakeWithReply:(void (^)(void))reply;

- (void)checkIfDirectoryExists:(NSString *)directory
                     withReply:(void (^)(NSNumber * _Nullable exists))reply;

- (void)runShellScript:(NSString *)script
                 shell:(NSString *)shell
             withReply:(void (^)(NSData * _Nullable output,
                                 NSData * _Nullable error,
                                 int status))reply;


@end

NS_ASSUME_NONNULL_END
