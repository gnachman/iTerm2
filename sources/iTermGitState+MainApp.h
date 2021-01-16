//
//  iTermGitState+MainApp.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/21.
//

#import "iTermGitState.h"

@class iTermVariableScope;

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitState (MainApp)
@property (nonatomic, readonly) NSTimeInterval age;

- (instancetype)initWithScope:(iTermVariableScope *)scope;

@end

@class iTermVariableScope;

@interface iTermRemoteGitStateObserver : NSObject

- (instancetype)initWithScope:(iTermVariableScope *)scope
                        block:(void (^)(void))block NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
