//
//  VT100SyncResult.h
//  iTerm2
//
//  Created by George Nachman on 1/17/22.
//

typedef struct {
    int overflow;
    BOOL haveScrolled;
    BOOL namedMarksChanged;
} VT100SyncResult;
