// The before version of the extractions in safe.c and broken.c. Each block
// is the lines between "// NAME{" and "// NAME}".
int work(int);
void use2(int, int);

void out_param(int x) {
    int y = 1;
    int z = 0;
    // out_param{
    z = work(x) * 2;
    y += z;
    // out_param}
    use2(y, z);
}

void return_flag(int x) {
    int y = 0;
    // return_flag{
    if (x < 0) {
        return;
    }
    y = work(x);
    // return_flag}
    use2(y, 0);
}

int break_flag(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        // break_flag{
        if (work(i) < 0) {
            break;
        }
        sum += i;
        // break_flag}
    }
    return sum;
}

void tail_return(int x) {
    work(x);
    // tail_return{
    if (x < 0) {
        return;
    }
    work(x + 1);
    // tail_return}
}

void not_inlined(int x) {
    int y = 1;
    int z = 0;
    // not_inlined{
    z = work(x) * 2;
    y += z;
    // not_inlined}
    use2(y, z);
}

int switch_case(int x) {
    int y = 0;
    switch (x) {
        case 1:
            // switch_case{
            if (work(x) < 0) {
                break;
            }
            y = work(x + 1);
            // switch_case}
            break;
        default:
            y = 2;
            break;
    }
    return y;
}

int switch_case_with_break(int x) {
    int y = 0;
    switch (x) {
        case 1: {
            // switch_case_with_break{
            if (work(x) < 0) {
                break;
            }
            y = work(x + 1);
            break;
            // switch_case_with_break}
        }
        default:
            y = 2;
            break;
    }
    return y;
}

void pointer_param(int *p, int x) {
    // pointer_param{
    p[0] = x;
    p[1] = work(x);
    // pointer_param}
    use2(p[0], x);
}

void take(int *);

void addr_param(int x) {
    int v = 0;
    // addr_param{
    take(&v);
    v += x;
    // addr_param}
    use2(v, x);
}

void inverted_flag(int x) {
    int y = 0;
    // inverted_flag{
    if (x < 0) {
        return;
    }
    y = work(x);
    // inverted_flag}
    use2(y, 0);
}

int dropped_tail(int x) {
    int y = 0;
    switch (x) {
        case 1:
            // dropped_tail{
            if (work(x) < 0) {
                break;
            }
            y = work(x + 1);
            // dropped_tail}
            y += 5;
            break;
        default:
            break;
    }
    return y;
}

void narrowing(int x) {
    int y = 0;
    // narrowing{
    y = work(x);
    // narrowing}
    use2(y, x);
}

void flag_mismatch(int x) {
    int y = 0;
    // flag_mismatch{
    if (x < 0) {
        return;
    }
    y = work(x);
    // flag_mismatch}
    use2(y, 0);
}

int valret(int a) {
    // valret{
    if (a) return 1;
    work(a);
    // valret}
    return 0;
}

int valret_tail(int a) {
    work(a);
    // valret_tail{
    if (a) return 1;
    return work(a);
    // valret_tail}
}

int valret_falloff(int a) {
    // valret_falloff{
    if (a) return 1;
    work(a);
    // valret_falloff}
    return 0;
}

int valbody(int a) {
    int b = a * 2;
    // valbody{
    if (b > 4) return 1;
    return b;
    // valbody}
}

int valbool(int a) {
    int b = a * 2;
    // valbool{
    if (b > 4) return 1;
    return b;
    // valbool}
}

int vallong(int a) {
    int b = a * 2;
    // vallong{
    if (b > 4) return 1;
    return b;
    // vallong}
}

void flag_other(int x) {
    int y = 0;
    // flag_other{
    if (x < 0) {
        return;
    }
    y = work(x);
    // flag_other}
    use2(y, 0);
}

void flag_final(int x) {
    int y = 0;
    // flag_final{
    if (x < 0) {
        return;
    }
    y = work(x);
    // flag_final}
    use2(y, 0);
}

int gtail;

void nested_tail(int a) {
    {
        // nested_tail{
        if (a > 3) return;
        gtail = a;
        // nested_tail}
    }
    gtail = 7;
}

void loop_tail(int n) {
    for (int i = 0; i < n; i++) {
        // loop_tail{
        if (work(i) < 0) return;
        gtail = i;
        // loop_tail}
    }
}

void retvar(int a) {
    int x = 0;
    // retvar{
    x = work(a) + 1;
    // retvar}
    use2(x, a);
}

void vpre(int a) {
    // vpre{
    gtail = a;
    gtail += 1;
    // vpre}
}

void caller_extra(int a) {
    use2(a, 0);
    // caller_extra{
    gtail = a;
    // caller_extra}
}

void removed_line(int a) {
    use2(a, 0);
    work(a);
    // removed_line{
    gtail = a;
    // removed_line}
}

int condret(int a) {
    int changed = 0;
    if (a > 1) changed = 1;
    // condret{
    if (work(a) > 0) {
        changed = 1;
    }
    // condret}
    return changed;
}

void placement(int a) {
    gtail = a;
    // placement{
    gtail += 2;
    // placement}
    use2(gtail, a);
}

int dshadow;

void decl_after(int a) {
    int dshadow = 0;
    // decl_after{
    dshadow = work(a) + 1;
    // decl_after}
    use2(dshadow, a);
}

void case_call(int x) {
    switch (x) {
        case 1:
            // case_call{
            gtail = work(x);
            // case_call}
            break;
        default:
            break;
    }
}

int exit_before(int a) {
    int x = 7;
    // exit_before{
    if (a < 0) return 0;
    x = work(a);
    // exit_before}
    return x + 1;
}
