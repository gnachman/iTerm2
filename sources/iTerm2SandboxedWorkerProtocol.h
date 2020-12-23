//
//  iTerm2SandboxedWorkerProtocol.h
//  iTerm2SandboxedWorker
//
//  Created by Benedek Kozma on 2020. 12. 23..
//

#import <Foundation/Foundation.h>

@class iTermImage;

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol iTerm2SandboxedWorkerProtocol

/**
 *https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW11
 *A method can have only one reply block. However, because connections are bidirectional, the XPC service helper can also reply by calling methods in the interface provided by the main application, if desired.
 *Each method must have a return type of void, and all parameters to methods or reply blocks must be either:
 * - Arithmetic types (int, char, float, double, uint64_t, NSUInteger, and so on)
 * - BOOL
 * - C strings
 * - C structures and arrays containing only the types listed above
 * - Objective-C objects that implement the NSSecureCoding protocol.
 */

- (void)decodeImageFromData:(NSData * _Nonnull)imageData withReply:(void (^_Nonnull)(iTermImage * _Nullable))reply;
    
@end

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     _connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"hu.cyberbeni.iTerm2SandboxedWorker"];
     _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(iTerm2SandboxedWorkerProtocol)];
     [_connectionToService resume];

Once you have a connection to the service, you can use it like this:

     [[_connectionToService remoteObjectProxy] upperCaseString:@"hello" withReply:^(NSString *aString) {
         // We have received a response. Update our text field, but do it on the main thread.
         NSLog(@"Result string was: %@", aString);
     }];

 And, when you are finished with the service, clean up the connection like this:

     [_connectionToService invalidate];
*/
