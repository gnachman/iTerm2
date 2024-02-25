//
//  TokenExecutorHelpers.m
//  iTerm2
//
//  Created by George Nachman on 2/29/24.
//

#import "TokenExecutorHelpers.h"

VT100Token *CVectorGetVT100Token(const CVector *vector, int index) {
    return (VT100Token *)vector->elements[index];
}
