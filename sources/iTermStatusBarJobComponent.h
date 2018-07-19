//
//  iTermStatusBarJobComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import "iTermStatusBarVariableBaseComponent.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarJobComponent : iTermStatusBarVariableBaseComponent

@property (nonatomic, readonly) pid_t pid;

@end

NS_ASSUME_NONNULL_END
