//
//  TokenExecutorHelpers.h
//  iTerm2
//
//  Created by George Nachman on 2/29/24.
//

#import <Foundation/Foundation.h>
#import "CVector.h"

@class VT100Token;

NS_ASSUME_NONNULL_BEGIN

// This keeps Swift from trying to do dynamic casting in a performance-critical loop.
VT100Token *CVectorGetVT100Token(const CVector *vector, int index);

NS_ASSUME_NONNULL_END
