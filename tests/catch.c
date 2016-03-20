#include <stdio.h>
#include <signal.h>
#include <unistd.h>

void InterruptHandler(int signo) {
  printf("Caught SIGINT\n");
}

int main(int argc, char *argv[]) {
  if (signal(SIGINT, InterruptHandler) == SIG_ERR) {
    printf("signal() returned an error.");
    return 1;
  }

  while(1) {
    sleep(1);
  }

  return 0;
}
