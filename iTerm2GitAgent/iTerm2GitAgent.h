//
//  iTerm2GitAgent.h
//  iTerm2GitAgent
//
//  Created by George Nachman on 7/28/21.
//

#import <Foundation/Foundation.h>
#import "iTerm2GitAgentProtocol.h"

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
@interface iTerm2GitAgent : NSObject <iTerm2GitAgentProtocol>
@end
