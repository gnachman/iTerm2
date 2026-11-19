// Correct extractions of the blocks in before.c. Each block is now the lines
// between "// NAME{" and "// NAME}" inside its helper.
int work(int);
void use2(int, int);

static void out_param_helper(int x, int *y, int *z) {
    // out_param{
    *z = work(x) * 2;
    *y += *z;
    // out_param}
}

void out_param(int x) {
    int y = 1;
    int z = 0;
    out_param_helper(x, &y, &z);
    use2(y, z);
}

static int return_flag_helper(int x, int *y) {
    // return_flag{
    if (x < 0) {
        return 1;
    }
    *y = work(x);
    // return_flag}
    return 0;
}

void return_flag(int x) {
    int y = 0;
    if (return_flag_helper(x, &y)) {
        return;
    }
    use2(y, 0);
}

static int break_flag_helper(int i, int *sum) {
    // break_flag{
    if (work(i) < 0) {
        return 1;
    }
    *sum += i;
    // break_flag}
    return 0;
}

int break_flag(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        if (break_flag_helper(i, &sum)) {
            break;
        }
    }
    return sum;
}

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
}

__attribute__((noinline)) static void not_inlined_helper(int x, int *y, int *z) {
    // not_inlined{
    *z = work(x) * 2;
    *y += *z;
    // not_inlined}
}

void not_inlined(int x) {
    int y = 1;
    int z = 0;
    not_inlined_helper(x, &y, &z);
    use2(y, z);
}

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
            break;
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
            break;
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

void take(int *);

static void addr_param_helper(int x, int *v) {
    // addr_param{
    take(v);
    *v += x;
    // addr_param}
}

void addr_param(int x) {
    int v = 0;
    addr_param_helper(x, &v);
    use2(v, x);
}

static int valret_tail_helper(int a) {
    // valret_tail{
    if (a) return 1;
    return work(a);
    // valret_tail}
}

int valret_tail(int a) {
    work(a);
    return valret_tail_helper(a);
}

static int valbody_helper(int b) {
    // valbody{
    if (b > 4) return 1;
    return b;
    // valbody}
}

int valbody(int a) {
    int b = a * 2;
    return valbody_helper(b);
}

int gtail;

static int retvar_helper(int a) {
    int x;
    // retvar{
    x = work(a) + 1;
    // retvar}
    return x;
}

void retvar(int a) {
    int x = 0;
    x = retvar_helper(a);
    use2(x, a);
}

static void placement_helper(void) {
    // placement{
    gtail += 2;
    // placement}
}

void placement(int a) {
    gtail = a;
    placement_helper();
    use2(gtail, a);
}

static void case_call_helper(int x) {
    // case_call{
    gtail = work(x);
    // case_call}
}

void case_call(int x) {
    switch (x) {
        case 1:
            case_call_helper(x);
            break;
        default:
            break;
    }
}
