//
//  CVector.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/22.
//

#import "CVector.h"

void CVectorReleaseObjects(const CVector *vector) {
    const int n = CVectorCount(vector);
    for (int i = 0; i < n; i++) {
        __unsafe_unretained id obj = CVectorGet(vector, i);
        [obj release];
    }
}
