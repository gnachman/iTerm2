// The before version of the C++ extractions in safe.mm and broken.mm.
struct Box { int v; };
void usei(int);

void refw(void) {
    int a = 1;
    int &r = a;
    // refw{
    r = 5;
    // refw}
    usei(a);
}

void setv(Box &b, int k) {
    // setv{
    if (k > 0) {
        b.v = k;
    }
    // setv}
}
