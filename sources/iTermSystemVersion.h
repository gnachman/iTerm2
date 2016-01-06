//
//  iTermSystemVersion.h
//  iTerm2
//
//  Created by George Nachman on 1/3/16.
//
//

#import <Foundation/Foundation.h>

BOOL IsYosemiteOrLater(void);
BOOL IsMavericksOrLater(void);
BOOL SystemVersionIsGreaterOrEqualTo(unsigned major, unsigned minor, unsigned bugfix);

