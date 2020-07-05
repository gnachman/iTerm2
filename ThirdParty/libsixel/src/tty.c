/*
 * Copyright (c) 2014-2016 Hayaki Saito
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include "config.h"

#if STDC_HEADERS
# include <stdio.h>
# include <stdlib.h>
#endif  /* HAVE_STDLIB_H */
#if HAVE_STRING_H
# include <string.h>
#endif  /* HAVE_STRING_H */
#if HAVE_SYS_TIME_H
# include <sys/time.h>
#endif  /* HAVE_SYS_TIME_H */
#if HAVE_SYS_TYPES_H
# include <sys/types.h>
#endif  /* HAVE_SYS_TYPES_H */
#if HAVE_UNISTD_H
# include <unistd.h>
#endif  /* HAVE_UNISTD_H */
#if HAVE_SYS_UNISTD_H
# include <sys/unistd.h>
#endif  /* HAVE_SYS_UNISTD_H */
#if HAVE_SYS_SELECT_H
# include <sys/select.h>
#endif  /* HAVE_SYS_SELECT_H */
#if HAVE_ERRNO_H
# include <errno.h>
#endif  /* HAVE_ERRNO_H */
#if HAVE_TERMIOS_H
# include <termios.h>
#endif  /* HAVE_TERMIOS_H */
#if HAVE_SYS_IOCTL_H
# include <sys/ioctl.h>
#endif  /* HAVE_SYS_IOCTL_H */

#include <sixel.h>

#if HAVE_TERMIOS_H && HAVE_SYS_IOCTL_H && HAVE_ISATTY
SIXELSTATUS
sixel_tty_cbreak(struct termios *old_termios, struct termios *new_termios)
{
    SIXELSTATUS status = SIXEL_FALSE;
    int ret;

    /* set the terminal to cbreak mode */
    ret = tcgetattr(STDIN_FILENO, old_termios);
    if (ret != 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message(
            "sixel_tty_cbreak: tcgetattr() failed.");
        goto end;
    }

    (void) memcpy(new_termios, old_termios, sizeof(*old_termios));
    new_termios->c_lflag &= (tcflag_t)~(ECHO | ICANON);
    new_termios->c_cc[VMIN] = 1;
    new_termios->c_cc[VTIME] = 0;

    ret = tcsetattr(STDIN_FILENO, TCSAFLUSH, new_termios);
    if (ret != 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message(
            "sixel_tty_cbreak: tcsetattr() failed.");
        goto end;
    }

    status = SIXEL_OK;

end:
    return status;
}
#endif  /* HAVE_TERMIOS_H && HAVE_SYS_IOCTL_H && HAVE_ISATTY */


#if HAVE_TERMIOS_H && HAVE_SYS_IOCTL_H && HAVE_ISATTY
SIXELSTATUS
sixel_tty_restore(struct termios *old_termios)
{
    SIXELSTATUS status = SIXEL_FALSE;
    int ret;

    ret = tcsetattr(STDIN_FILENO, TCSAFLUSH, old_termios);
    if (ret != 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message(
            "sixel_tty_restore: tcsetattr() failed.");
        goto end;
    }

    status = SIXEL_OK;

end:
    return status;
}
#endif  /* HAVE_TERMIOS_H && HAVE_SYS_IOCTL_H && HAVE_ISATTY */


SIXELSTATUS
sixel_tty_wait_stdin(int usec)
{
#if HAVE_SYS_SELECT_H
    fd_set rfds;
    struct timeval tv;
    int ret = 0;
#endif  /* HAVE_SYS_SELECT_H */
    SIXELSTATUS status = SIXEL_FALSE;

#if HAVE_SYS_SELECT_H
    tv.tv_sec = usec / 1000000;
    tv.tv_usec = usec % 1000000;
    FD_ZERO(&rfds);
    FD_SET(STDIN_FILENO, &rfds);
    ret = select(STDIN_FILENO + 1, &rfds, NULL, NULL, &tv);
    if (ret < 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message(
            "sixel_tty_wait_stdin: select() failed.");
        goto end;
    }

    /* success */
    status = SIXEL_OK;
#else
    (void) usec;
    goto end;
#endif  /* HAVE_SYS_SELECT_H */

end:
    return status;
}


SIXELSTATUS
sixel_tty_scroll(
    sixel_write_function f_write,
    int outfd,
    int height,
    int is_animation)
{
    SIXELSTATUS status = SIXEL_FALSE;
    int nwrite;
#if HAVE_TERMIOS_H && HAVE_SYS_IOCTL_H && HAVE_ISATTY
    struct winsize size = {0, 0, 0, 0};
    struct termios old_termios;
    struct termios new_termios;
    int row = 0;
    int col = 0;
    int cellheight;
    int scroll;
    char buffer[256];
    int result;

    /* confirm I/O file descriptors are tty devices */
    if (!isatty(STDIN_FILENO) || !isatty(outfd)) {
        /* set cursor position to top-left */
        nwrite = f_write("\033[H", 3, &outfd);
        if (nwrite < 0) {
            status = (SIXEL_LIBC_ERROR | (errno & 0xff));
            sixel_helper_set_additional_message(
                "sixel_tty_scroll: f_write() failed.");
            goto end;
        }
        status = SIXEL_OK;
        goto end;
    }

    /* request terminal size to tty device with TIOCGWINSZ ioctl */
    result = ioctl(outfd, TIOCGWINSZ, &size);
    if (result != 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message("ioctl() failed.");
        goto end;
    }

    /* if we can not retrieve terminal pixel size over TIOCGWINSZ ioctl,
       return immediatly */
    if (size.ws_ypixel <= 0) {
        nwrite = f_write("\033[H", 3, &outfd);
        if (nwrite < 0) {
            status = (SIXEL_LIBC_ERROR | (errno & 0xff));
            sixel_helper_set_additional_message(
                "sixel_tty_scroll: f_write() failed.");
            goto end;
        }
        status = SIXEL_OK;
        goto end;
    }

    /* if input source is animation and frame No. is more than 1,
       output DECSC sequence */
    if (is_animation) {
        nwrite = f_write("\0338", 2, &outfd);
        if (nwrite < 0) {
            status = (SIXEL_LIBC_ERROR | (errno & 0xff));
            sixel_helper_set_additional_message(
                "sixel_tty_scroll: f_write() failed.");
            goto end;
        }
        status = SIXEL_OK;
        goto end;
    }

    /* set the terminal to cbreak mode */
    status = sixel_tty_cbreak(&old_termios, &new_termios);
    if (SIXEL_FAILED(status)) {
        goto end;
    }

    /* request cursor position report */
    nwrite = f_write("\033[6n", 4, &outfd);
    if (nwrite < 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message(
            "sixel_tty_scroll: f_write() failed.");
        goto end;
    }

    /* wait cursor position report */
    if (SIXEL_FAILED(sixel_tty_wait_stdin(1000 * 1000))) { /* wait up to 1 sec */
        /* If we can't get any response from the terminal,
         * move cursor to (1, 1). */
        nwrite = f_write("\033[H", 3, &outfd);
        if (nwrite < 0) {
            status = (SIXEL_LIBC_ERROR | (errno & 0xff));
            sixel_helper_set_additional_message(
                "sixel_tty_scroll: f_write() failed.");
            goto end;
        }
        status = SIXEL_OK;
        goto end;
    }

    /* scan cursor position report */
    if (scanf("\033[%d;%dR", &row, &col) != 2) {
        nwrite = f_write("\033[H", 3, &outfd);
        if (nwrite < 0) {
            status = (SIXEL_LIBC_ERROR | (errno & 0xff));
            sixel_helper_set_additional_message(
                "sixel_tty_scroll: f_write() failed.");
            goto end;
        }
        status = SIXEL_OK;
        goto end;
    }

    /* restore the terminal mode */
    status = sixel_tty_restore(&old_termios);
    if (SIXEL_FAILED(status)) {
        goto end;
    }

    /* calculate scrolling amount in pixels */
    cellheight = height * size.ws_row / size.ws_ypixel + 1;
    scroll = cellheight + row - size.ws_row + 1;
    if (scroll > 0) {
        nwrite = sprintf(buffer, "\033[%dS\033[%dA", scroll, scroll);
        if (nwrite < 0) {
            status = (SIXEL_LIBC_ERROR | (errno & 0xff));
            sixel_helper_set_additional_message(
                "sixel_tty_scroll: sprintf() failed.");
        }
        nwrite = f_write(buffer, (int)strlen(buffer), &outfd);
        if (nwrite < 0) {
            status = (SIXEL_LIBC_ERROR | (errno & 0xff));
            sixel_helper_set_additional_message(
                "sixel_tty_scroll: f_write() failed.");
            goto end;
        }
    }

    /* emit DECSC sequence */
    nwrite = f_write("\0337", 2, &outfd);
    if (nwrite < 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message(
            "sixel_tty_scroll: f_write() failed.");
        goto end;
    }
#else  /* mingw */
    (void) height;
    (void) is_animation;
    nwrite = f_write("\033[H", 3, &outfd);
    if (nwrite < 0) {
        status = (SIXEL_LIBC_ERROR | (errno & 0xff));
        sixel_helper_set_additional_message(
            "sixel_tty_scroll: f_write() failed.");
        goto end;
    }
#endif  /* HAVE_TERMIOS_H && HAVE_SYS_IOCTL_H && HAVE_ISATTY */

    status = SIXEL_OK;

end:
    return status;
}

/* emacs Local Variables:      */
/* emacs mode: c               */
/* emacs tab-width: 4          */
/* emacs indent-tabs-mode: nil */
/* emacs c-basic-offset: 4     */
/* emacs End:                  */
/* vim: set expandtab ts=4 sts=4 sw=4 : */
/* EOF */
