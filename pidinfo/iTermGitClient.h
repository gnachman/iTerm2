//
//  iTermGitClient.h
//  pidinfo
//
//  Created by George Nachman on 1/11/21.
//

#import <Foundation/Foundation.h>

#import "iTermGitState.h"

#import "git2.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitClient : NSObject
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) git_repository *repo;

- (instancetype)initWithRepoPath:(NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (git_reference *)head;

- (const git_oid *)oidAtRef:(git_reference *)ref;

- (NSString *)branchAt:(git_reference *)ref;

- (BOOL)getCountsFromRef:(git_reference *)ref
                    pull:(NSInteger *)pullCount
                    push:(NSInteger *)pushCount;

- (BOOL)repoIsDirty;

- (BOOL)getDeletions:(NSInteger *)deletionsPtr
           untracked:(NSInteger *)untrackedPtr;

@end

@interface iTermGitState(GitClient)

+ (instancetype)gitStateForRepoAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
