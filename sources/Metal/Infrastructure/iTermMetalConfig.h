//
//  iTermMetalConfig.h
//  iTerm2
//
//  Created by George Nachman on 3/30/18.
//

// Perform most metal activities on a private queue? Relieves the main thread of most drawing
// work when enabled.
#define ENABLE_PRIVATE_QUEUE 1

// If enabled, the drawable's -present method is called on the main queue after the GPU work is
// scheduled. This is horrible and slow but is necessary if you set presentsWithTransaction
// to YES. That should be avoided at all costs.
#define ENABLE_SYNCHRONOUS_PRESENTATION 0

// It's not clear to me if dispatching to the main queue is actually necessary, but I'm leaving
// this here so it's easy to switch back to doing so. It adds a ton of latency when enabled.
#define ENABLE_DISPATCH_TO_MAIN_QUEUE_FOR_ENQUEUEING_DRAW_CALLS 0

#define ENABLE_PER_FRAME_METAL_STATS 0

#define ENABLE_USE_TEMPORARY_TEXTURE 1
