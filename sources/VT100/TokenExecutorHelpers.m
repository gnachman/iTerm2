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
void CVectorSetVT100Token(const CVector *vector, int index, VT100Token *token) {
    [(VT100Token *)vector->elements[index] release];
    vector->elements[index] = [token retain];
}
void CVectorAppendVT100Token(CVector *vector, VT100Token *token) {
    CVectorAppend(vector, (void *)[token retain]);
}
