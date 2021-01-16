//
//  pidinfoProtocol.h
//  pidinfo
//
//  Created by George Nachman on 1/11/20.
//

#import <Foundation/Foundation.h>

@class iTermGitState;

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

- (void)findCompletionsWithPrefix:(NSString *)prefix
                    inDirectories:(NSArray<NSString *> *)directories
                              pwd:(NSString *)pwd
                         maxCount:(NSInteger)maxCount
                       executable:(BOOL)executable
                        withReply:(void (^)(NSArray<NSString *> * _Nullable))reply;

- (void)requestGitStateForPath:(NSString *)path
                    completion:(void (^)(iTermGitState * _Nullable))completion;

- (void)fetchRecentBranchesAt:(NSString *)path count:(NSInteger)maxCount completion:(void (^)(NSArray<NSString *> *))reply;

@end

NS_ASSUME_NONNULL_END
