//
//  iTermGitState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;

@interface iTermGitState : NSObject<NSCopying>
@property (nonatomic, copy) NSString *xcode;
@property (nonatomic, copy) NSString *pushArrow;
@property (nonatomic, copy) NSString *pullArrow;
@property (nonatomic, copy) NSString *branch;
@property (nonatomic) BOOL dirty;
@property (nonatomic) NSInteger adds;
@property (nonatomic) NSInteger deletes;

- (instancetype)initWithScope:(iTermVariableScope *)scope;

@end

@class iTermVariableScope;

@interface iTermRemoteGitStateObserver : NSObject

- (instancetype)initWithScope:(iTermVariableScope *)scope
                        block:(void (^)(void))block NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
