//
//  PIDInfoGitState.h
//  pidinfo
//
//  Created by George Nachman on 4/27/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Write encoded git state to fd 0. If includeDiffStats is non-zero, also
// populates the richer diff stats fields; this requires running git_diff which
// can be expensive on large repos or slow filesystems.
void PIDInfoGetGitState(const char *cpath, int timeout, int includeDiffStats);

NS_ASSUME_NONNULL_END
