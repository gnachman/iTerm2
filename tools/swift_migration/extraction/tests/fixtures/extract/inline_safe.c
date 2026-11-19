// A correct extraction of the block in inline_before.c.
int work(int);

static void inlined_everywhere_helper(int *p, int x) {
    // inlined_everywhere{
    p[0] = x;
    p[1] = work(x);
    // inlined_everywhere}
}

static void inlined_everywhere(int *p, int x) {
    inlined_everywhere_helper(p, x);
}

void calls_inlined(int *p) {
    inlined_everywhere(p, 3);
}
