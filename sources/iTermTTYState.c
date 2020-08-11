//
//  iTermTTYState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/18/19.
//

#import "iTermTTYState.h"

#import "DebugLogging.h"
#import "iTermCLogging.h"

#include <stdbool.h>
#include <string.h>
#include <sys/ioctl.h>

static cc_t iTermTTYMakeControlKey(char c) {
    return c - 'A' + 1;
}

static bool iTermWinSizeEqualsTaskSize(struct winsize lhs, PTYTaskSize rhs) {
    if (lhs.ws_col != rhs.cellSize.width) {
        return false;
    }
    if (lhs.ws_row != rhs.cellSize.height) {
        return false;
    }
    if (lhs.ws_xpixel != rhs.pixelSize.width) {
        return false;
    }
    if (lhs.ws_ypixel != rhs.pixelSize.height) {
        return false;
    }
    return true;
}

void iTermTTYStateInit(iTermTTYState *ttyState,
                       iTermTTYCellSize cellSize,
                       iTermTTYPixelSize pixelSize,
                       int isUTF8) {
    struct termios *term = &ttyState->term;
    struct winsize *win = &ttyState->win;

    memset(term, 0, sizeof(struct termios));
    memset(win, 0, sizeof(struct winsize));

    // UTF-8 input will be added on demand.
    term->c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT | (isUTF8 ? IUTF8 : 0);
    term->c_oflag = OPOST | ONLCR;
    term->c_cflag = CREAD | CS8 | HUPCL;
    term->c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;

    term->c_cc[VEOF] = iTermTTYMakeControlKey('D');
    term->c_cc[VEOL] = -1;
    term->c_cc[VEOL2] = -1;
    term->c_cc[VERASE] = 0x7f;           // DEL
    term->c_cc[VWERASE] = iTermTTYMakeControlKey('W');
    term->c_cc[VKILL] = iTermTTYMakeControlKey('U');
    term->c_cc[VREPRINT] = iTermTTYMakeControlKey('R');
    term->c_cc[VINTR] = iTermTTYMakeControlKey('C');
    term->c_cc[VQUIT] = 0x1c;           // Control+backslash
    term->c_cc[VSUSP] = iTermTTYMakeControlKey('Z');
    term->c_cc[VDSUSP] = iTermTTYMakeControlKey('Y');
    term->c_cc[VSTART] = iTermTTYMakeControlKey('Q');
    term->c_cc[VSTOP] = iTermTTYMakeControlKey('S');
    term->c_cc[VLNEXT] = iTermTTYMakeControlKey('V');
    term->c_cc[VDISCARD] = iTermTTYMakeControlKey('O');
    term->c_cc[VMIN] = 1;
    term->c_cc[VTIME] = 0;
    term->c_cc[VSTATUS] = iTermTTYMakeControlKey('T');

    term->c_ispeed = B38400;
    term->c_ospeed = B38400;

    win->ws_row = cellSize.height;
    win->ws_col = cellSize.width;
    win->ws_xpixel = pixelSize.width;
    win->ws_ypixel = pixelSize.height;
}

static struct winsize iTermGetTerminalSize(int fd) {
    struct winsize winsize;
    ioctl(fd, TIOCGWINSZ, &winsize);
    return winsize;
}

static void iTermForceSetTerminalSize(int fd, PTYTaskSize taskSize) {
    struct winsize winsize = {
        .ws_col = taskSize.cellSize.width,
        .ws_row = taskSize.cellSize.height,
        .ws_xpixel = taskSize.pixelSize.width,
        .ws_ypixel = taskSize.pixelSize.height
    };

    FDLog(LOG_DEBUG, "Set window size to cells=(%d x %d) pixels=(%d x %d)",
         winsize.ws_col,
         winsize.ws_row,
         winsize.ws_xpixel,
         winsize.ws_ypixel);

    ioctl(fd, TIOCSWINSZ, &winsize);
}

void iTermSetTerminalSize(int fd, PTYTaskSize taskSize) {
    if (!iTermWinSizeEqualsTaskSize(iTermGetTerminalSize(fd), taskSize)) {
        iTermForceSetTerminalSize(fd, taskSize);
    }

}

iTermTTYPixelSize iTermTTYPixelSizeMake(double width, double height) {
    iTermTTYPixelSize result;
    if (width < 0) {
        result.width = 0;
    } else if (width > USHRT_MAX) {
        result.width = USHRT_MAX;
    } else {
        result.width = width;
    }
    if (height < 0) {
        result.height = 0;
    } else if (height > USHRT_MAX) {
        result.height = USHRT_MAX;
    } else {
        result.height = height;
    }
    return result;
}

iTermTTYCellSize iTermTTYCellSizeMake(double width, double height) {
    iTermTTYCellSize result;
    if (width < 0) {
        result.width = 0;
    } else if (width > USHRT_MAX) {
        result.width = USHRT_MAX;
    } else {
        result.width = width;
    }
    if (height < 0) {
        result.height = 0;
    } else if (height > USHRT_MAX) {
        result.height = USHRT_MAX;
    } else {
        result.height = height;
    }
    return result;
}

int PTYTaskSizeEqual(PTYTaskSize lhs, PTYTaskSize rhs) {
    return (lhs.pixelSize.width == rhs.pixelSize.width &&
            lhs.pixelSize.height == rhs.pixelSize.height &&
            lhs.cellSize.width == rhs.cellSize.width &&
            lhs.cellSize.height == rhs.cellSize.height);
}
