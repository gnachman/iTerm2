//
//  iTermResourceLimitsHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/12/19.
//

#import "iTermResourceLimitsHelper.h"

#include <sys/resource.h>

static struct rlimit sSavedLimits[RLIM_NLIMITS];
static int sGetRLimitStatus[RLIM_NLIMITS];

void iTermResourceLimitsHelperSaveCurrentLimits(void) {
    for (int i = 0; i < RLIM_NLIMITS; i++) {
        sGetRLimitStatus[i] = getrlimit(i, &sSavedLimits[i]);
    }
}

void iTermResourceLimitsHelperRestoreSavedLimits(void) {
    for (int i = 0; i < RLIM_NLIMITS; i++) {
        if (!sGetRLimitStatus[i]) {
            setrlimit(i, &sSavedLimits[i]);
        }
    }
}

