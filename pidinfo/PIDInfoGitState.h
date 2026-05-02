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
// can be expensive on large repos or slow filesystems. `gitBase` selects
// the ref the file-status diff runs against (NULL or "HEAD" → legacy
// status_list pass; anything else → diff-against-base path).
void PIDInfoGetGitState(const char *cpath,
                        int timeout,
                        int includeDiffStats,
                        const char * _Nullable gitBase);

NS_ASSUME_NONNULL_END
