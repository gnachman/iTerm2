//
//  iTermActivityInfo.h
//  iTerm2
//
//  Created by George Nachman on 1/16/21.
//

#import <Foundation/Foundation.h>

// Time intervals are time-since-boot.
typedef struct {
    // Time since we sent a CR or LF
    NSTimeInterval lastNewline;

    // Time since a redraw or other update.
    NSTimeInterval lastActivity;
} iTermActivityInfo;
