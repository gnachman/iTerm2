// Correct C++ extractions of the blocks in before.mm.
struct Box { int v; };
void usei(int);

static void refw_helper(int &r) {
    // refw{
    r = 5;
    // refw}
}

void refw(void) {
    int a = 1;
    int &r = a;
    refw_helper(r);
    usei(a);
}

static void setv_helper(Box &b, int k) {
    // setv{
    if (k > 0) {
        b.v = k;
    }
    // setv}
}

void setv(Box &b, int k) {
    setv_helper(b, k);
}
