//
//  iTerm2Service.m
//  iTerm2Service
//
//  Created by George Nachman on 10/31/16.
//
//

#import "iTerm2Service.h"

@implementation iTerm2Service

// This implements the example protocol. Replace the body of this class with the implementation of this service's protocol.
- (void)upperCaseString:(NSString *)aString withReply:(void (^)(NSString *))reply {
    NSString *response = [aString uppercaseString];
    reply(response);
}

@end
