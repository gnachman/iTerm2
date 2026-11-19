// A wrong extraction of the block in inline_before.c.
int work(int);

// The helper writes p[1] before p[0]: the order of the two writes changed.
static void inlined_everywhere_helper(int *p, int x) {
    // inlined_everywhere{
    p[1] = work(x);
    p[0] = x;
    // inlined_everywhere}
}

static void inlined_everywhere(int *p, int x) {
    inlined_everywhere_helper(p, x);
}

void calls_inlined(int *p) {
    inlined_everywhere(p, 3);
}
