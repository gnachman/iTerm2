// Fixture for test_coverage_report.py: see fold.h. The tests find lines by
// the "M:" markers.
#include "fold.h"
int gFlag;

int fold_loop(void) {
    int n = 0;
    do {
        n++;
      while (0) {  // M:while0
      }
    } while (0);
    return n;
}

int fold_macro(void) {
    return H();  // M:h-use
}

int main(void) {
    return fold_loop() + fold_macro() > 100;
}
