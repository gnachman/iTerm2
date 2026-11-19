// Fixture: one property of each kind of type classstate.importability
// classifies. test_codedb_classstate.py SwiftcAgreementTest asks swiftc what
// Swift imports of each, and the extractor for the facts of the ivar the
// compiler synthesizes for it, and checks that the two agree.
__attribute__((objc_root_class))
@interface ProbeRoot
@end
typedef enum { PlainA, PlainB } PlainEnum;
typedef enum __attribute__((enum_extensibility(open))) NiceEnum : long { NiceA, NiceB } NiceEnum;
typedef struct { __strong id obj; int x; } StrongS;
typedef struct { __weak id obj; int x; } WeakS;
typedef struct { __unsafe_unretained id obj; int x; } UnretS;
typedef struct { int n; char tail[]; } FlexS;
typedef union { int i; float f; } U;
typedef struct { unsigned a : 3; unsigned b : 5; } BitS;
typedef struct { __int128 big; int x; } I128S;
typedef struct Opaque Opaque;
// As the SDK's CF_BRIDGED_TYPE declares CGContextRef.
typedef struct __attribute__((objc_bridge(id))) BridgedThing *BridgedThingRef;
typedef int (*FnPtr)(int);
typedef int (*VarFnPtr)(int, ...);
typedef float Vec4 __attribute__((ext_vector_type(4)));
@interface Probe : ProbeRoot
@property PlainEnum plain;
@property NiceEnum nice;
@property __int128 big;
@property long double ld;
@property _Atomic(int) atom;
@property _Complex double cplx;
@property _Float16 half;
@property StrongS strongS;
@property WeakS weakS;
@property UnretS unretS;
@property FlexS flexS;
@property U u;
@property BitS bitS;
@property I128S i128S;
@property Opaque *opaque;
@property BridgedThingRef bridged;
@property FnPtr fn;
@property VarFnPtr varFn;
@property Vec4 vec;
@property void (^plainBlock)(PlainEnum);
@property void (^strongSBlock)(StrongS);
@property int *intPtr;
@property StrongS *strongSPtr;
@property SEL sel;
@property id object;
@end
