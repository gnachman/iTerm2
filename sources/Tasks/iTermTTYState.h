//
//  iTermTTYState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/18/19.
//

#include <limits.h>
#import <termios.h>

typedef struct {
    struct termios term;
    struct winsize win;
    char tty[PATH_MAX];
} iTermTTYState;

typedef struct {
    unsigned short width;
    unsigned short height;
} iTermTTYCellSize;

typedef struct {
    unsigned short width;
    unsigned short height;
} iTermTTYPixelSize;

iTermTTYPixelSize iTermTTYPixelSizeMake(double width, double height);
iTermTTYCellSize iTermTTYCellSizeMake(double width, double height);

typedef struct {
    iTermTTYCellSize cellSize;
    iTermTTYPixelSize pixelSize;
} PTYTaskSize;

void iTermTTYStateInit(iTermTTYState *ttyState,
                       iTermTTYCellSize gridSize,
                       iTermTTYPixelSize viewSize,
                       int isUTF8);

void iTermSetTerminalSize(int fd, PTYTaskSize taskSize);
int PTYTaskSizeEqual(PTYTaskSize lhs, PTYTaskSize rhs);

