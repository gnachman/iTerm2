// Fixture: sends in code that no path from the function's entry reaches,
// which the extractor marks (in_unreachable_code) and the compiler does not
// emit at -O0 (test_codedb_completeness.py, UnreachableCodeTest). Each form
// sends its own selectors: u.. are marked, n.. are not.
__attribute__((objc_root_class))
@interface U {
    Class isa;
}
- (int)u01; - (int)u02; - (int)u03; - (int)u04; - (int)u05; - (int)u06; - (int)u07; - (int)u08;
- (int)u09; - (int)u10:(int)a with:(int)b; - (int)u11; - (int)u12; - (int)u13; - (int)u14; - (int)u15;
- (int)n01; - (int)n02; - (int)n03; - (int)n04; - (int)n05; - (int)n06; - (int)n07; - (int)n08;
- (int)n09; - (int)n10; - (int)n11; - (int)n12; - (int)n13; - (int)n14; - (int)n15;
- (int)n16; - (int)n17; - (int)n18; - (int)n19;
@end
typedef enum { E0, E1 } E;
void Stop(const char *why) __attribute__((noreturn));
int StopInt(void) __attribute__((noreturn));
int use(int v);
void AnalyzerOnly(void) __attribute__((analyzer_noreturn));
// ITAssertWithMessage: an if whose condition folds, its arm noreturn.
#define ASSERT_MSG(c) do { if (!(c)) { Stop(#c); } } while (0)
// assert (ITDebugAssert in Development): a conditional operator.
#define MY_ASSERT(e) (__builtin_expect(!(e), 0) ? Stop(#e) : (void)0)

// Marked.
void AfterReturn(U *o) { return; [o u01]; }
void AfterNoreturn(U *o) { Stop("x"); [o u02]; }
void AfterFoldedIfNoreturn(U *o) { ASSERT_MSG(0); [o u03]; }
void AfterFoldedConditionalNoreturn(U *o) { MY_ASSERT(0); [o u04]; }
int AfterSwitchThatReturns(U *o, int n) { switch (n) { case 0: return 1; default: return 2; } return [o u05]; }
void AfterBreak(U *o) { for (;;) { break; [o u06]; } }
void AfterContinue(U *o, int n) { while (n--) { continue; [o u07]; } }
void AfterGoto(U *o) { goto out; [o u08]; out: ; }
void InBlock(U *o) { void (^b)(void) = ^{ return; [o u09]; }; b(); }
// The send of u10:with: comes after its noreturn argument; u11 before it.
void AfterNoreturnArgument(U *o) { use([o u10:[o u11] with:StopInt()]); }
void AfterThrow(U *o) { @throw (id)o; [o u12]; }
void AfterReturnInIf(U *o, int n) { if (n) { return; [o u13]; } [o n01]; }
void AfterBuiltinUnreachable(U *o) { __builtin_unreachable(); [o u15]; }
// Methods too.
@implementation U (Unreachable)
- (int)afterReturn { return 0; [self u14]; }
@end

// Not marked.
// A switch over an enum that lists every case and returns in each: the
// compiler emits the code after it (the value can be out of range).
int AfterCoveredEnumSwitch(U *o, E e) { switch (e) { case E0: return 1; case E1: return 2; } return [o n02]; }
// while (0): the compiler emits the body.
void WhileZero(U *o) { while (0) { [o n03]; } }
void AfterLoopWithBreak(U *o, int n) { while (1) { if (n) break; } [o n04]; }
// After while (1) without a break: the compiler drops it, the mark is not set
// (the loop's exit is kept in the graph).
void AfterInfiniteLoop(U *o) { while (1) {} [o n05]; }
// A label after a return that a goto reaches.
void LabelAfterReturn(U *o) { goto in; return; in: [o n06]; }
void TryCatchFinally(U *o) { @try { [o n07]; } @catch (id e) { [o n08]; } @finally { [o n09]; } }
// An assertion whose condition does not fold.
void AssertNotFolded(U *o, int n) { MY_ASSERT(n); [o n10]; ASSERT_MSG(n); [o n11]; }
// The folded if's skipped arm holds a label: the compiler emits both arms.
void FoldedIfWithLabel(U *o) { goto in; if (1) { Stop("x"); } else { in: ; } [o n12]; }
// A conditional operator inside a branch condition: both operands emitted.
void ConditionalInCondition(U *o, int n) { if (1 ? n : StopInt()) {} [o n13]; }
// A block written in unreachable code is not walked as reachable or not.
void BlockInDeadCode(U *o) { return; void (^b)(void) = ^{ [o n14]; }; b(); }
void Reached(U *o) { [o n15]; }
// Clang's CFG ends a path at these, but the code generator emits what follows:
// only a noreturn attribute (noreturn, _Noreturn, [[noreturn]]) and
// __builtin_unreachable end a path for the mark.
void AfterAssumeFalse(U *o) { __builtin_assume(0); [o n16]; }
void AfterTrap(U *o) { __builtin_trap(); [o n17]; }
void AfterDebugTrap(U *o) { __builtin_debugtrap(); [o n18]; }
void AfterAnalyzerNoreturn(U *o) { AnalyzerOnly(); [o n19]; }
