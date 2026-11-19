// Statics: the helper increments the other static.
void use(int);
static int s_hits;
static int s_misses;
int hits(void) { return s_hits; }
int misses(void) { return s_misses; }

static void touch_helper(int x) {
    // touch{
    if (x) {
        s_misses++;
    }
    // touch}
}

void touch(int x) {
    use(x);
    touch_helper(x);
}
