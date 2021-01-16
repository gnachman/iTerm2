//
//  iTermGitState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSArray<NSString *> *iTermGitStatePaths(void);

extern NSString *const iTermGitStateVariableNameGitBranch;
extern NSString *const iTermGitStateVariableNameGitPushCount;
extern NSString *const iTermGitStateVariableNameGitPullCount;
extern NSString *const iTermGitStateVariableNameGitDirty;
extern NSString *const iTermGitStateVariableNameGitAdds;
extern NSString *const iTermGitStateVariableNameGitDeletes;

typedef NS_ENUM(NSInteger, iTermGitRepoState) {
    iTermGitRepoStateNone,
    iTermGitRepoStateMerge,
    iTermGitRepoStateRevert,
    iTermGitRepoStateCherrypick,
    iTermGitRepoStateBisect,
    iTermGitRepoStateRebase,
    iTermGitRepoStateApply,
};

@interface iTermGitState : NSObject<NSCopying, NSSecureCoding>
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *xcode;
@property (nonatomic, copy) NSString *pushArrow;
@property (nonatomic, copy) NSString *pullArrow;
@property (nonatomic, copy) NSString *branch;
@property (nonatomic) BOOL dirty;
@property (nonatomic) NSInteger adds;
@property (nonatomic) NSInteger deletes;
@property (nonatomic) NSTimeInterval creationTime;
@property (nonatomic) iTermGitRepoState repoState;
@end


NS_ASSUME_NONNULL_END
