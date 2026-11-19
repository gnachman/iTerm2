// Fixtures for extract_check.py: data flow and other hazards. Each range is
// the lines between "// NAME{" and "// NAME}".
#include <alloca.h>
#include <setjmp.h>
#include <stdarg.h>
#include <string.h>

int work(int);
void take(int *);

int read_write(int a, int b) {
    int used_after = 0;
    int dead_after = 0;
    int only_read = a + b;
    // read_write{
    used_after = only_read * 2;
    dead_after = used_after + 1;
    work(dead_after);
    // read_write}
    return used_after;
}

int later_write_only(int a) {
    int x = 0;
    // later_write_only{
    x = a;
    work(x);
    // later_write_only}
    x = 5;
    return 0;
}

int address_taken(int a) {
    int x = a;
    // address_taken{
    take(&x);
    // address_taken}
    return x;
}

int address_taken_elsewhere(int a) {
    int x = a;
    int *p = &x;
    // address_taken_elsewhere{
    x = x + 1;
    // address_taken_elsewhere}
    return *p;
}

int loop_carried(int n) {
    int count = 0;
    for (int i = 0; i < n; i++) {
        // loop_carried{
        count = count + work(i);
        // loop_carried}
    }
    return 0;
}

int loop_local(int n) {
    for (int i = 0; i < n; i++) {
        int t = 0;
        // loop_local{
        t = t + work(i);
        // loop_local}
        work(t);
    }
    return 0;
}

int declared_inside(int a) {
    // declared_inside{
    int fresh = a * 3;
    work(fresh);
    // declared_inside}
    return fresh;
}

int struct_member(int a) {
    struct { int x; int y; } s = {0, 0};
    // struct_member{
    s.x = a;
    // struct_member}
    return s.x + s.y;
}

int array_element(int a) {
    int arr[4] = {0};
    // array_element{
    arr[1] = a;
    // array_element}
    return arr[0] + arr[1];
}

int array_decay(int a) {
    char buf[16];
    // array_decay{
    memset(buf, a, sizeof buf);
    // array_decay}
    return buf[0];
}

int unevaluated(int a) {
    int x = a;
    // unevaluated{
    work((int)sizeof(x));
    // unevaluated}
    return 0;
}

int vla(int n) {
    int v[n];
    // vla{
    v[0] = n;
    // vla}
    return v[0];
}

int uses_alloca(int n) {
    char *p = 0;
    // uses_alloca{
    p = alloca(n);
    p[0] = 1;
    // uses_alloca}
    return p[0];
}

int uses_va(int n, ...) {
    va_list ap;
    int total = 0;
    // uses_va{
    va_start(ap, n);
    total = va_arg(ap, int);
    va_end(ap);
    // uses_va}
    return total;
}

static jmp_buf gJump;

int uses_setjmp(int n) {
    int r = 0;
    // uses_setjmp{
    r = setjmp(gJump);
    // uses_setjmp}
    return r + n;
}

int static_local(int n) {
    static int calls = 0;
    // static_local{
    calls++;
    // static_local}
    return calls + n;
}

int backward_goto(int n) {
    int x = 0;
again:
    work(x);
    // backward_goto{
    x = x + 1;
    // backward_goto}
    if (x < n) goto again;
    return 0;
}

int cleanup_attr(int n) {
    // cleanup_attr{
    int __attribute__((cleanup(take))) guard = n;
    work(guard);
    // cleanup_attr}
    return 0;
}

int frame_address(int n) {
    void *p = 0;
    // frame_address{
    p = __builtin_frame_address(0);
    // frame_address}
    return p != 0;
}

#define UNIQUE(x) x##__COUNTER__
int counter(int n) {
    int r = 0;
    // counter{
    r = n + 1;
    work(__COUNTER__);
    // counter}
    return r;
}

int compound_only(int a) {
    int acc = a;
    // compound_only{
    acc += 2;
    // compound_only}
    return acc;
}

static int s_counter;
int g_file;

void globals(void) {
    // globals{
    s_counter++;
    g_file = 2;
    // globals}
}

void ptr_through(int *p) {
    // ptr_through{
    *p = 3;
    // ptr_through}
}

int escape_local(void) {
    int *p = 0;
    // escape_local{
    int y = 5;
    p = &y;
    // escape_local}
    return *p;
}

struct Pair { int a; int b; };
int escape_literal(void) {
    struct Pair *ps = 0;
    // escape_literal{
    ps = &(struct Pair){1, 2};
    // escape_literal}
    return ps->a;
}

int alias_before(void) {
    int x = 1;
    int *p = &x;
    // alias_before{
    x = 3;
    // alias_before}
    return *p;
}

void c_block(void) {
    void (^b)(void) = ^{ work(1); };
    // c_block{
    b();
    // c_block}
}

typedef float float4 __attribute__((ext_vector_type(4)));
float simd(void) {
    float4 v = {0, 0, 0, 0};
    // simd{
    v.x = 1;
    // simd}
    return v.y + v.x;
}

int charptr(char *s) {
    int n = 0;
    // charptr{
    n = s[0];
    // charptr}
    return n;
}

int sizeof_outer(void) {
    int arr[8] = {0};
    int n = 0;
    // sizeof_outer{
    n = (int)(sizeof(arr) / sizeof(arr[0]));
    // sizeof_outer}
    return n + arr[0];
}
