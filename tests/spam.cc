#include <stdio.h>
#include <stdlib.h>
int cm;

void setline(char* s, int n) {
  int l = random() % n;
  if (cm) l *= 3;
  int j;
  for (j = 0; j < l && j < n; ++j) {
    if (cm && j + 6 < l && (random() % 3) == 0 ) {
      int r = random() %26;
      s[j++] = 0xef;
      s[j++] = 0xbc;
      s[j] = 0xa0 + r;
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
  cm = 1;
  for (int i = 0; n < 0 || i < n; ++i) {
    char buffer[10000];
    setline(buffer, sizeof(buffer)-1);
    printf("%s\n", buffer);
  }
  return 0;
}

