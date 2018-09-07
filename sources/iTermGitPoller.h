//
//  iTermGitPoller.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermGitState;

@interface iTermGitPoller : NSObject
@property (nonatomic) NSTimeInterval cadence;
@property (nonatomic, copy) NSString *currentDirectory;
@property (nonatomic) BOOL enabled;
@property (nonatomic, readonly) iTermGitState *state;

- (instancetype)initWithCadence:(NSTimeInterval)cadence
                         update:(void (^)(void))update NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
