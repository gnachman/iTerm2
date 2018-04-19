//
//  iTermAPIHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import <Foundation/Foundation.h>
#import "iTermAPIServer.h"

extern NSString *const iTermRemoveAPIServerSubscriptionsNotification;

@interface iTermAPIHelper : NSObject<iTermAPIServerDelegate>

- (void)postAPINotification:(ITMNotification *)notification toConnection:(id)connection;

@end
