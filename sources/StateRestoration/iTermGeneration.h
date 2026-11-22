//
//  iTermGeneration.h
//  iTerm2SharedARC
//
//  The one source of generation numbers for state restoration's delta encoder.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The delta encoder reuses a saved record when an object reports the same generation as the
// record. So a generation must never equal one written for different content, including one
// written by an earlier run of the app. Everything that gives the encoder a generation takes it
// from here, which guarantees that:
//
// - Numbers increase for the life of the process and are never handed out twice.
// - The counter starts at zero. Nothing is saved until the saved state has loaded (or failed to
//   load, which discards it). Once it loads, iTermGraphDatabase adds a baseline above every
//   generation in it, so numbers handed out from then on differ from last run's. If it never
//   loads, there is nothing to differ from and the baseline is effectively zero.
//
// To mark an object changed, give it a fresh number with iTermGenerationNext(). Never increment a
// generation in place: the result may collide with a number allocated elsewhere.
//
// Thread-safe.
FOUNDATION_EXTERN NSInteger iTermGenerationNext(void);

// Adds `baseline` to the counter, so every later value of iTermGenerationNext() exceeds
// `baseline`. iTermGraphDatabase calls this once the saved state has loaded, with a baseline above
// every generation in it.
FOUNDATION_EXTERN void iTermGenerationAddBaseline(NSInteger baseline);

// For an object that restores saved state by merging it into what it already holds, which an
// app-wide object may have changed before the saved state loaded. `current` is the object's
// generation, 0 if it hasn't changed since launch. Returns `saved` if it hadn't, so unchanged state
// can skip its next save. Otherwise the merged content matches neither the object's old content
// nor the saved record, so returns a fresh generation, which is past `saved`.
FOUNDATION_EXTERN NSInteger iTermGenerationAdopt(NSInteger current, NSInteger saved);

// Future values of iTermGenerationNext() will be greater than `generation`. For objects that adopt
// a generation from saved state that might not have come from the database.
FOUNDATION_EXTERN void iTermGenerationRaiseFloorAbove(NSInteger generation);

NS_ASSUME_NONNULL_END
