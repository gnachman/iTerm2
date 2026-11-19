// Fixture header for test_coverage_report.py: H()'s condition gFlag sits at
// line 10, column 14, the same coordinates as the while (0) of
// foldmain.c, whose true outcome is folded.
extern int gFlag;





#define H() (gFlag ? 1 : 0)  // M:h-cond
