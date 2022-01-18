//
//  VT100Screen+Mutation.h
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

#import "VT100Screen.h"

NS_ASSUME_NONNULL_BEGIN

@interface VT100Screen (Mutation)

- (void)mutResetDirty;

@end

NS_ASSUME_NONNULL_END
