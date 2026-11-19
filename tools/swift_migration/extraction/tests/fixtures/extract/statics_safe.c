// Statics: correct extractions.
void use(int);
static int s_hits;
static int s_misses;
int hits(void) { return s_hits; }
int misses(void) { return s_misses; }

static void touch_helper(int x) {
    // touch{
    if (x) {
        s_hits++;
    }
    // touch}
}

void touch(int x) {
    use(x);
    touch_helper(x);
}

// always_inline so that the comparison can see the static local renamed.
__attribute__((always_inline)) static void counter_fn_helper(int x) {
    // moved_static{
    static int calls;
    calls += x;
    use(calls);
    // moved_static}
}

void counter_fn(int x) {
    use(x);
    counter_fn_helper(x);
}
