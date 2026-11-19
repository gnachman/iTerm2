// Wrong extractions of the blocks in before.c, one defect each. Each block is
// now the lines between "// NAME{" and "// NAME}" inside its helper.
int work(int);
void use2(int, int);

// The write to z is not passed back.
static void out_param_helper(int x, int *y, int z) {
    // out_param{
    z = work(x) * 2;
    *y += z;
    // out_param}
}

void out_param(int x) {
    int y = 1;
    int z = 0;
    out_param_helper(x, &y, z);
    use2(y, z);
}

// The return now leaves only the helper.
static void return_flag_helper(int x, int *y) {
    // return_flag{
    if (x < 0) {
        return;
    }
    *y = work(x);
    // return_flag}
}

void return_flag(int x) {
    int y = 0;
    return_flag_helper(x, &y);
    use2(y, 0);
}

// The break became a return from the helper, and the loop carries on.
static void break_flag_helper(int i, int *sum) {
    // break_flag{
    if (work(i) < 0) {
        return;
    }
    *sum += i;
    // break_flag}
}

int break_flag(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        break_flag_helper(i, &sum);
    }
    return sum;
}

// The call is no longer the last thing the caller does.
static void tail_return_helper(int x) {
    // tail_return{
    if (x < 0) {
        return;
    }
    work(x + 1);
    // tail_return}
}

void tail_return(int x) {
    work(x);
    tail_return_helper(x);
    work(0);
}

__attribute__((noinline)) static void not_inlined_helper(int x, int *y, int z) {
    // not_inlined{
    z = work(x) * 2;
    *y += z;
    // not_inlined}
}

void not_inlined(int x) {
    int y = 1;
    int z = 0;
    not_inlined_helper(x, &y, z);
    use2(y, z);
}

// The break became a return, and the call is not followed by a break: the
// case falls through into default.
static void switch_case_helper(int x, int *y) {
    // switch_case{
    if (work(x) < 0) {
        return;
    }
    *y = work(x + 1);
    // switch_case}
}

int switch_case(int x) {
    int y = 0;
    switch (x) {
        case 1:
            switch_case_helper(x, &y);
        default:
            y = 2;
            break;
    }
    return y;
}

static void switch_case_with_break_helper(int x, int *y) {
    // switch_case_with_break{
    if (work(x) < 0) {
        return;
    }
    *y = work(x + 1);
    return;
    // switch_case_with_break}
}

int switch_case_with_break(int x) {
    int y = 0;
    switch (x) {
        case 1: {
            switch_case_with_break_helper(x, &y);
        }
        default:
            y = 2;
            break;
    }
    return y;
}

static void pointer_param_helper(int *p, int x) {
    // pointer_param{
    p[0] = x;
    p[1] = work(x);
    // pointer_param}
}

void pointer_param(int *p, int x) {
    pointer_param_helper(p, x);
    use2(p[0], x);
}

// The caller tests the flag the wrong way round.
static int inverted_flag_helper(int x, int *y) {
    // inverted_flag{
    if (x < 0) {
        return 1;
    }
    *y = work(x);
    // inverted_flag}
    return 0;
}

void inverted_flag(int x) {
    int y = 0;
    if (!inverted_flag_helper(x, &y)) {
        return;
    }
    use2(y, 0);
}

// The call is followed by break, but the code after the block (y += 5) is gone.
static void dropped_tail_helper(int x, int *y) {
    // dropped_tail{
    if (work(x) < 0) {
        return;
    }
    *y = work(x + 1);
    // dropped_tail}
}

int dropped_tail(int x) {
    int y = 0;
    switch (x) {
        case 1:
            dropped_tail_helper(x, &y);
            break;
        default:
            break;
    }
    return y;
}

// x is passed through a narrower parameter.
static void narrowing_helper(char x, int *y) {
    // narrowing{
    *y = work(x);
    // narrowing}
}

void narrowing(int x) {
    int y = 0;
    narrowing_helper(x, &y);
    use2(y, x);
}

// The helper returns 2 at the exit, but the caller tests for 1: neither value
// takes the branch.
static int flag_mismatch_helper(int x, int *y) {
    // flag_mismatch{
    if (x < 0) {
        return 2;
    }
    *y = work(x);
    // flag_mismatch}
    return 0;
}

void flag_mismatch(int x) {
    int y = 0;
    if (flag_mismatch_helper(x, &y) == 1) {
        return;
    }
    use2(y, 0);
}

// The code after the block (return 0) is gone; the helper returns 7 instead.
static int valret_helper(int a) {
    // valret{
    if (a) return 1;
    work(a);
    // valret}
    return 7;
}

int valret(int a) {
    return valret_helper(a);
}

// The returned value changed at the mapped line.
static int valret_tail_helper(int a) {
    // valret_tail{
    if (a) return 2;
    return work(a);
    // valret_tail}
}

int valret_tail(int a) {
    work(a);
    return valret_tail_helper(a);
}

// The helper's body is exactly the block, but the block could fall through
// to "return 0", which the caller no longer runs: the helper falls off its end.
static int valret_falloff_helper(int a) {
    // valret_falloff{
    if (a) return 1;
    work(a);
    // valret_falloff}
}

int valret_falloff(int a) {
    return valret_falloff_helper(a);
}

// The helper changes b before the moved lines.
static int valbody_helper(int b) {
    b++;
    // valbody{
    if (b > 4) return 1;
    return b;
    // valbody}
}

int valbody(int a) {
    int b = a * 2;
    return valbody_helper(b);
}

// The helper returns _Bool: return b becomes 0 or 1.
static _Bool valbool_helper(int b) {
    // valbool{
    if (b > 4) return 1;
    return b;
    // valbool}
}

int valbool(int a) {
    int b = a * 2;
    return valbool_helper(b);
}

// The helper returns long.
static long vallong_helper(int b) {
    // vallong{
    if (b > 4) return 1;
    return b;
    // vallong}
}

int vallong(int a) {
    int b = a * 2;
    return vallong_helper(b);
}

// Another return in the helper also takes the branch.
static int flag_other_helper(int x, int *y) {
    // flag_other{
    if (x < 0) {
        return 1;
    }
    if (x > 100) return 1;
    // flag_other}
    return 0;
}

void flag_other(int x) {
    int y = 0;
    if (flag_other_helper(x, &y)) {
        return;
    }
    use2(y, 0);
}

// The helper's final return takes the branch too.
static int flag_final_helper(int x, int *y) {
    // flag_final{
    if (x < 0) {
        return 1;
    }
    *y = work(x);
    // flag_final}
    return 1;
}

void flag_final(int x) {
    int y = 0;
    if (flag_final_helper(x, &y)) {
        return;
    }
    use2(y, 0);
}

int gtail;

static void nested_tail_helper(int a) {
    // nested_tail{
    if (a > 3) return;
    gtail = a;
    // nested_tail}
}

void nested_tail(int a) {
    {
        nested_tail_helper(a);
    }
    gtail = 7;
}

static void loop_tail_helper(int i) {
    // loop_tail{
    if (work(i) < 0) return;
    gtail = i;
    // loop_tail}
}

void loop_tail(int n) {
    for (int i = 0; i < n; i++) {
        loop_tail_helper(i);
    }
}

// The helper changes a before the moved lines.
static void vpre_helper(int a) {
    a = 5;
    // vpre{
    gtail = a;
    gtail += 1;
    // vpre}
}

void vpre(int a) {
    vpre_helper(a);
}

// The caller gains a statement besides the call.
static void caller_extra_helper(int a) {
    // caller_extra{
    gtail = a;
    // caller_extra}
}

void caller_extra(int a) {
    use2(a, 0);
    gtail = 9;
    caller_extra_helper(a);
}

// The caller loses work(a), which was not part of the block.
static void removed_line_helper(int a) {
    // removed_line{
    gtail = a;
    // removed_line}
}

void removed_line(int a) {
    use2(a, 0);
    removed_line_helper(a);
}

// changed is written only on some paths: its earlier value is lost.
static int condret_helper(int a) {
    int changed = 0;
    // condret{
    if (work(a) > 0) {
        changed = 1;
    }
    // condret}
    return changed;
}

int condret(int a) {
    int changed = 0;
    if (a > 1) changed = 1;
    changed = condret_helper(a);
    return changed;
}

// The call is one statement earlier than the block was.
static void placement_helper(void) {
    // placement{
    gtail += 2;
    // placement}
}

void placement(int a) {
    placement_helper();
    gtail = a;
    use2(gtail, a);
}

int dshadow;

// The moved line writes the global dshadow; the helper then returns a new local.
static int decl_after_helper(int a) {
    // decl_after{
    dshadow = work(a) + 1;
    // decl_after}
    int dshadow = 5;
    return dshadow;
}

void decl_after(int a) {
    int dshadow = 0;
    dshadow = decl_after_helper(a);
    use2(dshadow, a);
}

// x is assigned after a possible exit: on that path the helper returns x unassigned.
static int exit_before_helper(int a) {
    int x;
    // exit_before{
    if (a < 0) return 0;
    x = work(a);
    // exit_before}
    return x;
}

int exit_before(int a) {
    int x = 7;
    x = exit_before_helper(a);
    return x + 1;
}
