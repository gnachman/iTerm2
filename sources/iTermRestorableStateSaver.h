//
//  iTermRestorableStateSaver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import <Cocoa/Cocoa.h>

#import "iTermRestorableStateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermRestorableStateSaver : NSObject<iTermRestorableStateSaver>
@property (nonatomic) BOOL needsSave;
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, readonly) NSURL *indexURL;

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                     indexURL:(NSURL *)indexURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
