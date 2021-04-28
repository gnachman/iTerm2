//
//  PIDInfoGitState.h
//  pidinfo
//
//  Created by George Nachman on 4/27/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Write encoded git state to fd 0.
void PIDInfoGetGitState(const char *cpath, int timeout);

NS_ASSUME_NONNULL_END
