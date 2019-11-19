//
//  iTermTTYState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/18/19.
//

#import <AppKit/AppKit.h>

#import "VT100GridTypes.h"

#include <limits.h>
#import <termios.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    struct termios term;
    struct winsize win;
    char tty[PATH_MAX];
} iTermTTYState;

typedef struct {
    VT100GridSize gridSize;
    NSSize viewSize;
} PTYTaskSize;

void iTermTTYStateInit(iTermTTYState *ttyState,
                       VT100GridSize gridSize,
                       NSSize viewSize,
                       BOOL isUTF8);

NS_INLINE NSSize iTermTTYClampWindowSize(NSSize viewSize) {
    return NSMakeSize(MAX(0, MIN(viewSize.width, USHRT_MAX)),
                      MAX(0, MIN(viewSize.height, USHRT_MAX)));
}

void iTermSetTerminalSize(int fd, PTYTaskSize taskSize);

NS_ASSUME_NONNULL_END
