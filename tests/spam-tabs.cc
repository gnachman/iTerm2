#include <stdio.h>
#include <stdlib.h>
int cm;

void setline(char* s, int n) {
  int l = random() % n;
  if (cm) l *= 3;
  int j;
  for (j = 0; j < l; ++j) {
    int r = random();
    if (cm && (r % 20)==0) {
      r = random() % 5 + 1;
      for (int k = 0; k < r; k++) {
        s[j++] = '\t';
      }
    } else {
      s[j] = 'A' + (random() % 60);
    }
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
  cm = argc==3;
  for (int i = 0; i < n; ++i) {
    char buffer[100];
    setline(buffer, sizeof(buffer)-1);
    printf("%s\n", buffer);
  }
  return 0;
}

