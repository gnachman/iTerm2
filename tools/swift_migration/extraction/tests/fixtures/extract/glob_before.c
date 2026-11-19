// Compiler-emitted globals in C: the before version.
static const int T1[4] = {1, 2, 3, 4};
static const int T2[4] = {1, 2, 3, 4};
int use(const int *);
void run(int (^b)(void));
int counter;
static int m1, m2;
static int *const P1 = &m1;
static int *const P2 = &m2;
int peek(void) { return m1 + m2 + T1[0] + T2[0] + *P1 + *P2; }
int pick(int k);

int table(int i) {
    counter++;
    // table{
    counter += use(T1) + i;
    // table}
    return counter;
}

void ptrconst(int i) {
    counter++;
    // ptrconst{
    *P1 = i;
    // ptrconst}
    counter--;
}

void blockmoved(int n) {
    counter += n;
    // blockmoved{
    run(^{ return 1; });
    // blockmoved}
    counter--;
}

int sw(int k) {
    int r = 0;
    // sw{
    switch (k) {
        case 0: r = 10; break;
        case 1: r = 7; break;
        case 2: r = 33; break;
        case 3: r = 2; break;
        case 4: r = 91; break;
        case 5: r = 5; break;
        default: r = 0; break;
    }
    // sw}
    return r + counter;
}
