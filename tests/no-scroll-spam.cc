#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
void setline(char* s, int n) {
  int l = random() % n;
  int j;
  for (j = 0; j < l; ++j) {
    s[j] = 'A' + (random() % 60);
  }
  s[j] = 0;
}

int main(int argc, char*argv[]) {
  int n;
  if (argc == 1) {
    n = 1000000;
  } else {
    n = atoi(argv[1]);
  }
  for (int i = 0; i < n; ++i) {
    char buffer[100];
    setline(buffer, sizeof(buffer)-1);
    printf("%s\n", buffer);
    //usleep(100000);
    if (i % 10 == 0) {
      printf("%c[H", 27);
    }
  }
  printf("%c[2J\n", 27);
  return 0;
}

