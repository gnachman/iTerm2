// Fixtures for extract_check.py: control flow. Each range to analyze is the
// lines between a "// NAME{" line and the matching "// NAME}" line.
#include <stdlib.h>

#define CHECK(x) do { if (!(x)) return -1; } while (0)
#define SAFE_LOG(x) do { if (x) { log_value(x); } } while (0)

void log_value(int);
int work(int);

int return_external(int x) {
    int y = 0;
    // return_external{
    if (x < 0) {
        return -1;
    }
    y = x * 2;
    // return_external}
    return y;
}

int return_in_macro(int x) {
    int y = 0;
    // return_in_macro{
    CHECK(x >= 0);
    y = x + 1;
    // return_in_macro}
    return y;
}

int macro_without_exit(int x) {
    int y = 0;
    // macro_without_exit{
    SAFE_LOG(x);
    y = x + 1;
    // macro_without_exit}
    return y;
}

int switch_break_internal(int x) {
    int y = 0;
    // switch_break_internal{
    switch (x) {
        case 1:
            y = 10;
            break;
        default:
            y = 20;
            break;
    }
    // switch_break_internal}
    return y;
}

int break_outer_loop(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        // break_outer_loop{
        if (work(i) < 0) {
            break;
        }
        sum += i;
        // break_outer_loop}
    }
    return sum;
}

int continue_outer_loop(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        // continue_outer_loop{
        if (work(i) < 0) {
            continue;
        }
        sum += i;
        // continue_outer_loop}
    }
    return sum;
}

int loop_inside_range(int n) {
    int sum = 0;
    // loop_inside_range{
    for (int i = 0; i < n; i++) {
        if (work(i) < 0) {
            break;
        }
        if (i == 3) {
            continue;
        }
        sum += i;
    }
    // loop_inside_range}
    return sum;
}

int goto_fail(int x) {
    int err = 0;
    // goto_fail{
    err = work(x);
    if (err) goto fail;
    err = work(x + 1);
    // goto_fail}
    if (err) goto fail;
    return 0;
fail:
    return err;
}

int goto_internal(int x) {
    int err = 0;
    // goto_internal{
    err = work(x);
    if (err) goto done;
    err = work(x + 1);
done:
    err = err + 1;
    // goto_internal}
    return err;
}

int goto_into(int x) {
    int err = 0;
    if (x) goto again;
    // goto_into{
    err = work(x);
again:
    err = err + 1;
    // goto_into}
    return err;
}

int statement_expression(int x) {
    int y = 0;
    // statement_expression{
    y = ({ int t = work(x); if (t < 0) return t; t + 1; });
    // statement_expression}
    return y;
}

int noreturn_call(int x) {
    int y = 0;
    // noreturn_call{
    if (x < 0) abort();
    y = x;
    // noreturn_call}
    return y;
}

int case_label_entry(int x) {
    int y = 0;
    switch (x) {
        case 0:
            y = 1;
            break;
        // case_label_entry{
        case 1:
            y = 2;
            break;
        // case_label_entry}
        default:
            break;
    }
    return y;
}

int case_body_only(int x) {
    int y = 0;
    switch (x) {
        case 1:
            // case_body_only{
            y = work(2);
            y += 3;
            // case_body_only}
            break;
        default:
            break;
    }
    return y;
}

int misaligned(int x) {
    int y = 0;
    if (x > 0) {
        y = 1;
    // misaligned{
    } else {
        y = 2;
    // misaligned}
    }
    return y;
}

int not_compiled(int x) {
    int y = 0;
    // not_compiled{
    y = x;
#if 0
    if (y) return 5;
#endif
    y += 1;
    // not_compiled}
    return y;
}

int not_compiled_after(int x) {
    int y = 0;
    // not_compiled_after{
    y = x + 1;
    // not_compiled_after}
#ifdef SOME_UNDEFINED_FLAG
    work(y);
#endif
    return 0;
}

int only_comments(int x) {
    // only_comments{
    // nothing here
    // only_comments}
    return x;
}
