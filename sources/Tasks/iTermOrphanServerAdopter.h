//
//  iTermOrphanServerAdopter.h
//  iTerm2
//
//  Created by George Nachman on 6/7/15.
//
//

#import <Foundation/Foundation.h>
#import "PTYTask.h"

// NS_ASSUME_NONNULL added by Window Projects work so claimedChildPIDsProvider's
// _Nullable below doesn't trigger a partial-nullability-audit error on every
// other pointer in this file.
NS_ASSUME_NONNULL_BEGIN

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

// Multiserver child PIDs that another subsystem (Window Projects cold storage)
// owns and will re-adopt on demand. The adopter must NOT pull these into a
// generic recovered window at startup; it leaves them in unattachedChildren so
// a project restore can re-attach them later. Evaluated lazily during adoption.
@property(nonatomic, copy) NSSet<NSNumber *> * _Nullable (^claimedChildPIDsProvider)(void);

+ (instancetype)sharedInstance;
// Pre-existing declaration (not Window Projects work); marked _Nullable
// because iTermApplicationDelegate.m has pre-existing call sites passing nil.
// TODO revert if upstream annotates this itself.
- (void)openWindowWithOrphansWithCompletion:(void (^ _Nullable)(void))completion;
- (void)removePath:(NSString *)path;
- (void)adoptPartialAttachments:(NSArray<id<iTermPartialAttachment>> *)partialAttachments;

@end

NS_ASSUME_NONNULL_END
