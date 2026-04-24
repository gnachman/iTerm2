//
//  iTermOrphanServerAdopter.h
//  iTerm2
//
//  Created by George Nachman on 6/7/15.
//
//

#import <Foundation/Foundation.h>
#import "PTYTask.h"

@class PTYSession;

@protocol iTermOrphanServerAdopterDelegate<NSObject>
- (void)orphanServerAdopterOpenSessionForConnection:(iTermGeneralServerConnection)connection
                                           inWindow:(id)window
                                         completion:(void (^)(PTYSession *))completion;

- (void)orphanServerAdopterOpenSessionForPartialAttachment:(id<iTermPartialAttachment>)partialAttachment
                                                  inWindow:(id)window
                                                completion:(void (^)(PTYSession *))completion;
@end

@interface iTermOrphanServerAdopter : NSObject

@property(nonatomic, readonly) BOOL haveOrphanServers;
@property(nonatomic, weak) id<iTermOrphanServerAdopterDelegate> delegate;

+ (instancetype)sharedInstance;
- (void)openWindowWithOrphansWithCompletion:(void (^)(void))completion;
- (void)removePath:(NSString *)path;
- (void)adoptPartialAttachments:(NSArray<id<iTermPartialAttachment>> *)partialAttachments;

@end
