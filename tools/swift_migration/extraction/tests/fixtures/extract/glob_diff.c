// Another table and pointer with equal contents, another block result and switch value: compares different.
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

static void table_helper(int i) {
    // table{
    counter += use(T2) + i;
    // table}
}

int table(int i) {
    counter++;
    table_helper(i);
    return counter;
}

static void ptrconst_helper(int i) {
    // ptrconst{
    *P2 = i;
    // ptrconst}
}

void ptrconst(int i) {
    counter++;
    ptrconst_helper(i);
    counter--;
}

static void blockmoved_helper(void) {
    // blockmoved{
    run(^{ return 2; });
    // blockmoved}
}

void blockmoved(int n) {
    counter += n;
    blockmoved_helper();
    counter--;
}

static int sw_helper(int k) {
    int r;
    // sw{
    switch (k) {
        case 0: r = 11; break;
        case 1: r = 7; break;
        case 2: r = 33; break;
        case 3: r = 2; break;
        case 4: r = 91; break;
        case 5: r = 5; break;
        default: r = 0; break;
    }
    // sw}
    return r;
}

int sw(int k) {
    int r = 0;
    r = sw_helper(k);
    return r + counter;
}
