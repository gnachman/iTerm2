// Statics: the before version.
void use(int);
static int s_hits;
static int s_misses;
int hits(void) { return s_hits; }
int misses(void) { return s_misses; }

void touch(int x) {
    use(x);
    // touch{
    if (x) {
        s_hits++;
    }
    // touch}
}

void counter_fn(int x) {
    use(x);
    // moved_static{
    static int calls;
    calls += x;
    use(calls);
    // moved_static}
}
