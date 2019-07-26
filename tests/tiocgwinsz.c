#include <stdio.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    struct winsize ws = { 0 };
    ioctl(STDOUT_FILENO,
          TIOCGWINSZ,
          &ws);

    printf("cells: %dx%d\npixels: %dx%d\n",
           ws.ws_row, ws.ws_col, ws.ws_xpixel, ws.ws_ypixel);
    return 0;
}
