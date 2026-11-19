// The before version of an extraction from a static function that the optimizer inlines into
// its only caller, so that the compiled comparison has to compare the whole file.
int work(int);

static void inlined_everywhere(int *p, int x) {
    // inlined_everywhere{
    p[0] = x;
    p[1] = work(x);
    // inlined_everywhere}
}

void calls_inlined(int *p) {
    inlined_everywhere(p, 3);
}
