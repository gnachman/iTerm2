// Fixture for tools/swift_migration/tests/test_coverage_report.py: C++
// lambdas, called and never called (a lambda never called has no coverage
// record at all), and C++ try/catch, whose catch bodies get their own
// regions. The tests find lines by the "M:" markers. main() says which
// paths run.

#include <stdexcept>
#include <cstdio>

extern "C" int l_mixed(int x) {
    auto called = [](int y) { return y > 0 ? 1 : 0; };  // M:l-called
    auto never = [x](int y) { return y * x; };  // M:l-never
    (void)never;
    return called(x);
}

extern "C" int l_all_called(int x) {
    auto twice = [&](int y) { return y * 2 + x; };  // M:l-twice
    return twice(x);
}

static void cthrow(int x) {
    if (x) {
        throw std::runtime_error("x");
    }
}

extern "C" int l_try(int x) {
    int r = 0;
    try {
        cthrow(x);
        r = 1;
    } catch (const std::runtime_error &e) {  // M:cxx-catch
        r = 2;
    }
    return r;
}

int main() {
    int t = l_mixed(1) + l_mixed(-1);
    t += l_all_called(2);
    t += l_try(0);
    std::printf("%d\n", t);
    return 0;
}
