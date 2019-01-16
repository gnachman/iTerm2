//
//  iTermGitPoller.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermGitPoller;
@class iTermGitState;

@protocol iTermGitPollerDelegate <NSObject>

- (BOOL)gitPollerShouldPoll:(iTermGitPoller *)poller;

@end

@interface iTermGitPoller : NSObject
@property (nonatomic) NSTimeInterval cadence;
@property (nonatomic, copy) NSString *currentDirectory;
@property (nonatomic) BOOL enabled;
@property (nonatomic, readonly) iTermGitState *state;
@property (nonatomic, weak) id<iTermGitPollerDelegate> delegate;

- (instancetype)initWithCadence:(NSTimeInterval)cadence
                         update:(void (^)(void))update NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

// Poll immediately if possible.
- (void)bump;

@end

NS_ASSUME_NONNULL_END
