// Fixture header for test_coverage_report.py: a static function compiled
// into two translation units, tu1.c and tu2.c, called the same way by each.
static inline int inl_sign(int x) {
    if (x > 0) {  // M:inl-if
        return 1;
    }
    return 0;
}
