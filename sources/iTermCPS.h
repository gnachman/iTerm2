//
//  iTermCPS.h
//  iTerm2
//
//  Created by George Nachman on 12/5/15.
//
//

// Bits of the no-longer-distributed (if ever?) CPS.h for the long-deprecated CoreProcessServices
// methods that we need to steal keyboard focus.

typedef struct CPSProcessSerNum {
    UInt32 lo;
    UInt32 hi;

    UInt32 extra[4];  // Just in case Apple makes this bigger some day.
} CPSProcessSerNum;

// See functions in FutureMethods.h to get pointers to CPS functions we use.