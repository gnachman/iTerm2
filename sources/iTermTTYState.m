//
//  iTermTTYState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/18/19.
//

#import "iTermTTYState.h"

#import "DebugLogging.h"

#include <sys/ioctl.h>

static cc_t iTermTTYMakeControlKey(char c) {
    return c - 'A' + 1;
}

static BOOL iTermWinSizeEqualsTaskSize(struct winsize lhs, PTYTaskSize rhs) {
    if (lhs.ws_col != rhs.gridSize.width) {
        return NO;
    }
    if (lhs.ws_row != rhs.gridSize.height) {
        return NO;
    }
    if (lhs.ws_xpixel != rhs.viewSize.width) {
        return NO;
    }
    if (lhs.ws_ypixel != rhs.viewSize.height) {
        return NO;
    }
    return YES;
}

void iTermTTYStateInit(iTermTTYState *ttyState,
                       VT100GridSize gridSize,
                       NSSize viewSize,
                       BOOL isUTF8) {
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

    NSSize safeViewSize = iTermTTYClampWindowSize(viewSize);
    win->ws_row = gridSize.height;
    win->ws_col = gridSize.width;
    win->ws_xpixel = safeViewSize.width;
    win->ws_ypixel = safeViewSize.height;
}

static struct winsize iTermGetTerminalSize(int fd) {
    struct winsize winsize;
    ioctl(fd, TIOCGWINSZ, &winsize);
    return winsize;
}

static void iTermForceSetTerminalSize(int fd, PTYTaskSize taskSize) {
    struct winsize winsize = {
        .ws_col = taskSize.gridSize.width,
        .ws_row = taskSize.gridSize.height,
        .ws_xpixel = taskSize.viewSize.width,
        .ws_ypixel = taskSize.viewSize.height
    };

    DLog(@"Set window size to cells=(%d x %d) pixels=(%d x %d)",
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
