// Fixtures for extract_check.py: C++ in Objective-C++. Each range is the lines
// between "// NAME{" and "// NAME}".

int work(int);

struct Guard {
    Guard();
    ~Guard();
    void poke();
    int peek() const;
};

struct Copyable {
    Copyable();
    Copyable(const Copyable &);
    int value;
};

template <typename F> void later(F f) { f(); }
void bump(int &);
void look(const int &);

int lambda_byref(int n) {
    int total = 0;
    // lambda_byref{
    later([&] { total += n; });
    // lambda_byref}
    return total;
}

int lambda_copy(int n) {
    int total = 0;
    // lambda_copy{
    later([total] { work(total); });
    // lambda_copy}
    return total + n;
}

int destructor_inside(int n) {
    // destructor_inside{
    Guard g;
    g.poke();
    // destructor_inside}
    return work(n);
}

int member_calls(int n) {
    Guard g;
    // member_calls{
    work(g.peek());
    g.poke();
    // member_calls}
    return n;
}

int references(int n) {
    int a = n, b = n;
    // references{
    bump(a);
    look(b);
    // references}
    return a + b;
}

int throw_internal(int n) {
    int r = 0;
    // throw_internal{
    try {
        if (n < 0) throw 1;
        r = n;
    } catch (int) {
        r = -1;
    }
    // throw_internal}
    return r;
}

int throw_external(int n) {
    int r = 0;
    try {
        // throw_external{
        if (n < 0) throw 1;
        r = n;
        // throw_external}
    } catch (int) {
        r = -1;
    }
    return r;
}

int copy_by_value(int n) {
    Copyable c;
    // copy_by_value{
    work(c.value + n);
    // copy_by_value}
    return 0;
}

int range_for(int n) {
    int values[3] = {1, 2, 3};
    int sum = 0;
    // range_for{
    for (int &v : values) {
        v += n;
        sum += v;
    }
    // range_for}
    return sum + values[0];
}

int lifetime_extended(int n) {
    // lifetime_extended{
    const Copyable &c = Copyable();
    work(c.value + n);
    // lifetime_extended}
    return 0;
}

struct It {
    int *p;
    bool operator!=(const It &o) const;
    It &operator++();
    int &operator*() const;
};
struct Seq {
    It begin() const;
    It end() const;
};
struct Num {
    int v;
    Num &operator+=(int k);
    explicit operator bool() const;
};

int operators(Seq s, Num n) {
    int total = 0;
    auto twice = [](int k) { return 2 * k; };
    // operators{
    for (int &x : s) {
        total += twice(x);
    }
    n += total;
    if (n) {
        total++;
    }
    // operators}
    return total;
}

int ref_write(void) {
    int a = 1;
    int &r = a;
    // ref_write{
    r = 5;
    // ref_write}
    return a;
}

struct P2 { int a; int b; };
int bindings(P2 p) {
    auto [x, y] = p;
    int r = 0;
    // bindings{
    r = x + y;
    // bindings}
    return r;
}
