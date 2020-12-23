//
//  iTermSandboxedWorkerClient.m
//  iTerm2SharedARC
//
//  Created by Benedek Kozma on 2020. 12. 23..
//

#import "iTermSandboxedWorkerClient.h"
#import "iTerm2SandboxedWorkerProtocol.h"
#import "DebugLogging.h"


@implementation iTermSandboxedWorkerClient

+ (NSXPCConnection *)connection {
    @synchronized(self) {
        static NSXPCConnection *sSandboxedWorkerConnection;
        if (sSandboxedWorkerConnection) {
            return sSandboxedWorkerConnection;
        }
        sSandboxedWorkerConnection = [[NSXPCConnection alloc] initWithServiceName:@"com.iterm2.sandboxed-worker"];
        if (!sSandboxedWorkerConnection) {
            return nil;
        }
        sSandboxedWorkerConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(iTerm2SandboxedWorkerProtocol)];
        sSandboxedWorkerConnection.invalidationHandler = ^{
            @synchronized(self) {
                sSandboxedWorkerConnection = nil;
            }
        };
        [sSandboxedWorkerConnection resume];
        return sSandboxedWorkerConnection;
    }
}

+ (iTermImage *)performSynchronously:(void (^ NS_NOESCAPE)(NSXPCConnection *connection, void (^completion)(iTermImage *)))block {
    NSXPCConnection *connectionToService = [self connection];

    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    __block iTermImage *result = nil;
    block(connectionToService, ^(iTermImage *image) {
        result = image;
        dispatch_group_leave(group);
    });

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    return result;
}

+ (iTermImage *)imageFromData:(NSData *)data {
    return [self performSynchronously:^(NSXPCConnection *connectionToService, void (^completion)(iTermImage *)) {
        [[connectionToService remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull error) {
            XLog(@"Failed to connect to service: %@", error);
            completion(nil);
        }] decodeImageFromData:data withReply:^(iTermImage * _Nullable image) {
            completion(image);
        }];
    }];
}

+ (iTermImage *)imageFromSixelData:(NSData *)data {
    return [self performSynchronously:^(NSXPCConnection *connectionToService, void (^completion)(iTermImage *)) {
        [[connectionToService remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull error) {
            XLog(@"Failed to connect to service: %@", error);
            completion(nil);
        }] decodeImageFromSixelData:data withReply:^(iTermImage * _Nullable image) {
            completion(image);
        }];
    }];
}

@end
