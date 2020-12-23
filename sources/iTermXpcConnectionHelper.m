//
//  iTermXpcConnectionHelper.m
//  iTerm2SharedARC
//
//  Created by Benedek Kozma on 2020. 12. 23..
//

#import "iTermXpcConnectionHelper.h"
#import "iTerm2SandboxedWorkerProtocol.h"
#import "DebugLogging.h"

@implementation iTermXpcConnectionHelper

+ (iTermImage *)imageFromData:(NSData *)data {
    __block iTermImage *retVal;
    NSXPCConnection *connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"hu.cyberbeni.iTerm2SandboxedWorker"];
    if (connectionToService) {
        __block NSLock *lock = [NSLock new];
        [lock lock];
        connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(iTerm2SandboxedWorkerProtocol)];
        [connectionToService resume];
        [[connectionToService remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull error) {
            XLog(@"Failed to connect to service: %@", error);
            [lock unlock];
        }] decodeImageFromData:data withReply:^(iTermImage * _Nullable image) {
            retVal = image;
            [lock unlock];
        }];
        [lock lock];
        [connectionToService invalidate];
    }
    return retVal;
}

@end
