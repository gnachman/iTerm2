//
//  iTermFileDescriptorMultiClientPendingLaunch.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import <Foundation/Foundation.h>

#import "iTermFileDescriptorMultiClientChild.h"
#import "iTermMultiServerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

typedef iTermCallback<id, iTermResult<iTermFileDescriptorMultiClientChild *> *> iTermMultiClientLaunchCallback;

@interface iTermFileDescriptorMultiClientPendingLaunch: NSObject
@property (nonatomic, readonly) iTermMultiServerRequestLaunch launchRequest;
@property (nonatomic, readonly) iTermMultiClientLaunchCallback *launchCallback;

- (instancetype)initWithRequest:(iTermMultiServerRequestLaunch)request
                       callback:(iTermMultiClientLaunchCallback *)callback
                         thread:(iTermThread *)thread NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)invalidate;
- (void)cancelWithError:(NSError *)error;
@end

NS_ASSUME_NONNULL_END
