//
//  MomentermCCStatusBarComponentImpl.h
//  iTerm2
//
//  Status bar component showing Claude Code usage:
//  workspace>project | branch | 5H ####------ 40% 3h 0m | 7D ##-------- 20% 5d 12h | $108.06 | sonnet
//

#import <Foundation/Foundation.h>
#import "iTermStatusBarBaseComponent.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kMomentermCCStatusBarIdentifier;

@interface MomentermCCStatusBarComponentImpl : iTermStatusBarBaseComponent

@end

NS_ASSUME_NONNULL_END
