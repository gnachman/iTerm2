//
//  iTermSystemVersion.h
//  iTerm2
//
//  Created by George Nachman on 1/3/16.
//
//

#import <Cocoa/Cocoa.h>

BOOL IsYosemiteOrLater(void);
BOOL IsMavericksOrLater(void);
BOOL IsElCapitanOrLater(void);
BOOL IsSierraOrLater(void);

BOOL SystemVersionIsGreaterOrEqualTo(unsigned major, unsigned minor, unsigned bugfix);
BOOL IsTouchBarAvailable(void);
