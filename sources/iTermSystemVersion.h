//
//  iTermSystemVersion.h
//  iTerm2
//
//  Created by George Nachman on 1/3/16.
//
//

#import <Cocoa/Cocoa.h>

BOOL IsElCapitanOrLater(void);  // 10.11
BOOL IsSierraOrLater(void);  // 10.12

BOOL SystemVersionIsGreaterOrEqualTo(unsigned major, unsigned minor, unsigned bugfix);
BOOL IsTouchBarAvailable(void);  // 10.12.2, but only if a selector exists.
