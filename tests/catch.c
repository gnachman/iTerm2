#include <stdio.h>
#include <signal.h>
#include <unistd.h>

sig_atomic_t caught_sigint = 0;

void InterruptHandler(int signo) {
  caught_sigint = 1;
}

int main(int argc, char *argv[]) {
  if (signal(SIGINT, InterruptHandler) == SIG_ERR) {
    printf("signal() returned an error.");
    return 1;
  }

  while(1) {
    sleep(1);
    if (caught_sigint) {
      printf("Caught SIGINT\n");
      caught_sigint = 0;
    }
  }
}
