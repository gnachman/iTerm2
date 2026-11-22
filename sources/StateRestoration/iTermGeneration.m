//
//  iTermGeneration.m
//  iTerm2SharedARC
//

#import "iTermGeneration.h"

#import "iTermGraphEncoder.h"

#import <stdatomic.h>

// The next value to hand out. Starts at 1, not 0: objects commonly start with a generation of 0
// before their first change, and that change must produce a different value.
static _Atomic NSInteger gNextGeneration = 1;

NSInteger iTermGenerationNext(void) {
    const NSInteger result = atomic_fetch_add_explicit(&gNextGeneration, 1, memory_order_relaxed);
    assert(result != iTermGenerationAlwaysEncode);
    return result;
}

void iTermGenerationAddBaseline(NSInteger baseline) {
    if (baseline <= 0) {
        return;
    }
    atomic_fetch_add_explicit(&gNextGeneration, baseline, memory_order_relaxed);
}

NSInteger iTermGenerationAdopt(NSInteger current, NSInteger saved) {
    iTermGenerationRaiseFloorAbove(saved);
    if (current == 0) {
        return saved;
    }
    return iTermGenerationNext();
}

void iTermGenerationRaiseFloorAbove(NSInteger generation) {
    if (generation == iTermGenerationAlwaysEncode || generation < 0) {
        return;
    }
    const NSInteger minimum = generation + 1;
    NSInteger expected = atomic_load_explicit(&gNextGeneration, memory_order_relaxed);
    while (expected < minimum &&
           !atomic_compare_exchange_weak_explicit(&gNextGeneration, &expected, minimum,
                                                  memory_order_relaxed, memory_order_relaxed)) {
        // expected was reloaded by the failed exchange.
    }
}
