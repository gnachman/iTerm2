#include <stdio.h>
#include <stdlib.h>
int cm;

void setline(char* s, int n) {
  int l = random() % n;
  if (cm) l *= 3;
  int j;
  for (j = 0; j < l; ++j) {
    if (cm) {
      int r = random() %30 + 1;
      s[j++] = 0xe0;
      s[j++] = 0xb8;
      s[j++] = 0x80 | r;
      s[j++] = 0xcc;
      s[j] = 0x80;
    } else {
      s[j] = 'A' + (random() % 60);
    }
  }
  s[j] = 0;
}

int main(int argc, char*argv[]) {
  int n;
  if (argc == 1) {
    n = 20000;
  } else {
    n = atoi(argv[1]);
  }
  cm = argc==3;
  for (int i = 0; n < 0 || i < n; ++i) {
    char buffer[10000];
    setline(buffer, sizeof(buffer)-1);
    printf("%s\n", buffer);
  }
  return 0;
}

