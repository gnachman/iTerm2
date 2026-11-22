// Fixture: unreachable code in Objective-C++ (test_codedb_completeness.py,
// UnreachableCodeTest): u.. are marked, n.. are not, t.. see below.
__attribute__((objc_root_class))
@interface UX {
    Class isa;
}
- (int)u01; - (int)u02; - (int)u03;
- (int)t01; - (int)n02; - (int)n03;
@end
[[noreturn]] void Fail();
int use(int v);

void AfterThrow(UX *o) { throw 1; [o u01]; }
void InLambda(UX *o) { auto f = [o] { return; [o u02]; }; f(); }
void AfterNoreturn(UX *o) { Fail(); [o u03]; }
// A template: the instantiation is marked, the pattern (never emitted) is not.
template <typename T> int InTemplate(T *o) { return 0; [o t01]; }
int Instantiate(UX *o) { return InTemplate(o); }
void TryCatch(UX *o) { try { [o n02]; } catch (...) { [o n03]; } }
