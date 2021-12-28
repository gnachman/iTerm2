//
//  VT100ScreenMutableState.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import <Foundation/Foundation.h>
#import "VT100ScreenState.h"

NS_ASSUME_NONNULL_BEGIN

@interface VT100ScreenMutableState: VT100ScreenState<VT100ScreenMutableState, NSCopying>
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *currentDirectoryDidChangeOrderEnforcer;
@property (nullable, nonatomic, strong) VT100InlineImageHelper *inlineImageHelper;
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *setWorkingDirectoryOrderEnforcer;

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (id<VT100ScreenState>)copy;
@end

NS_ASSUME_NONNULL_END
