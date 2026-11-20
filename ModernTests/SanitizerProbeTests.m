//
//  SanitizerProbeTests.m
//  ModernTests
//
//  Proves that the sanitizer test modes of the Objective-C to Swift migration
//  work (docs/swift-migration/phase0.md section 4). Each test commits exactly
//  one violation of one sanitizer group, through code in this file, so that a
//  run of this class under tools/swift_migration/sanitizer_tests.sh shows the
//  report (and, for nullability, the abort).
//
//  Every test is skipped unless the environment variable
//  ITERM2_SANITIZER_PROBE names its group. Only sanitizer_tests.sh sets it,
//  and only when asked to with --probe, so the ordinary test runner and a
//  sanitizer run of the whole suite skip all of these tests.
//
//      ITERM2_SANITIZER_PROBE=nullability  testNullabilityProbe
//      ITERM2_SANITIZER_PROBE=integer      testSignedOverflowProbe,
//                                          testImplicitTruncationProbe
//      ITERM2_SANITIZER_PROBE=thread       testDataRaceProbe
//
//  The values are kept opaque to the optimizer (volatile reads, a noinline
//  function) so that the violation happens at run time and is not folded
//  away or diagnosed at compile time.
//

#import <XCTest/XCTest.h>

#import <pthread.h>
#import <stdatomic.h>

// Defined here so that the nullability check sees a call to a function whose
// parameter is declared _Nonnull.
__attribute__((noinline))
static NSUInteger SanitizerProbeLengthOfNonnullString(NSString * _Nonnull string) {
    return string.length;
}

// A value the compiler cannot see through.
static volatile int gSanitizerProbeOne = 1;
static volatile int gSanitizerProbeWide = 0x12345;

// The variable the thread probe races on. It is a plain int on purpose.
static int gSanitizerProbeRacyValue;
static atomic_int gSanitizerProbeWriterDone;

static void *SanitizerProbeWriter(void *unused) {
    gSanitizerProbeRacyValue = 1;
    // Relaxed ordering creates no happens-before edge for the thread
    // sanitizer, so the main thread's write below races with the one above
    // even though it always happens after it in real time.
    atomic_store_explicit(&gSanitizerProbeWriterDone, 1, memory_order_relaxed);
    return NULL;
}

@interface SanitizerProbeTests : XCTestCase
@end

@implementation SanitizerProbeTests

- (void)skipUnlessProbing:(NSString *)group {
    NSString *probe = NSProcessInfo.processInfo.environment[@"ITERM2_SANITIZER_PROBE"];
    if (![probe isEqualToString:group]) {
        XCTSkip(@"Set ITERM2_SANITIZER_PROBE=%@ (tools/swift_migration/sanitizer_tests.sh --probe) to run this probe", group);
    }
}

// Expected under the nullability mode: a "null pointer passed as argument"
// report for SanitizerProbeLengthOfNonnullString, then the test host aborts.
- (void)testNullabilityProbe {
    [self skipUnlessProbing:@"nullability"];
    NSString *missing = NSProcessInfo.processInfo.environment[@"ITERM2_SANITIZER_PROBE_UNSET_VARIABLE"];
    XCTAssertEqual(SanitizerProbeLengthOfNonnullString(missing), 0u);
}

// Expected under the integer mode: "signed integer overflow".
- (void)testSignedOverflowProbe {
    [self skipUnlessProbing:@"integer"];
    int value = INT_MAX;
    value += gSanitizerProbeOne;
    XCTAssertEqual(value, INT_MIN);
}

// Expected under the integer mode: "implicit conversion from type 'int' of
// value 74565 ... to type 'uint8_t' ... changed the value to 69".
- (void)testImplicitTruncationProbe {
    [self skipUnlessProbing:@"integer"];
    int wide = gSanitizerProbeWide;
    uint8_t narrow = wide;
    XCTAssertEqual(narrow, 0x45);
}

// Expected under the thread mode: "data race" on gSanitizerProbeRacyValue
// between the writer thread and the main thread. There is no sleep: the main
// thread waits for the writer with a relaxed atomic, which orders the two
// writes in time but not for the thread sanitizer.
- (void)testDataRaceProbe {
    [self skipUnlessProbing:@"thread"];
    atomic_store_explicit(&gSanitizerProbeWriterDone, 0, memory_order_relaxed);
    pthread_t writer;
    XCTAssertEqual(pthread_create(&writer, NULL, SanitizerProbeWriter, NULL), 0);
    while (!atomic_load_explicit(&gSanitizerProbeWriterDone, memory_order_relaxed)) {
    }
    gSanitizerProbeRacyValue = 2;
    pthread_join(writer, NULL);
    XCTAssertEqual(gSanitizerProbeRacyValue, 2);
}

@end
