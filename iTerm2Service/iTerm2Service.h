//
//  iTerm2Service.h
//  iTerm2Service
//
//  Created by George Nachman on 10/31/16.
//
//

#import <Foundation/Foundation.h>
#import "iTerm2ServiceProtocol.h"

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@interface iTerm2Service : NSObject <iTerm2ServiceProtocol>
@end
