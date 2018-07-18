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

// When ASCII characters overlap each other, first draw "main" part of characters, tne copy to the
// intermediate texture, then draw non-main parts using blending to fix it up.
#define ENABLE_PRETTY_ASCII_OVERLAP 1

// Pretty ASCII overlap requires the use of a temporary texture as a scratchpad.
#define ENABLE_USE_TEMPORARY_TEXTURE ENABLE_PRETTY_ASCII_OVERLAP

//I've had to disable this feature because it appears to tickle a race condition. It dies saying:
//"[CAMetalLayerDrawable texture] should not be called after already presenting this drawable. Get a nextDrawable instead"
//That gets logged when accessing the texture immediately after getting a drawable and before it
//has been presented. However, that drawable gets touched in two different threads at different
// points in time, and another drawable gets presented at about the same time in a different thread.
// So my theory is that MTKView.currentDrawable can be used in a thread besides the main thread but
// it always has to be the *same* thread.
#define ENABLE_DEFER_CURRENT_DRAWABLE 0

// This is not 100% baked, but since the OS appears to be busted I'm not going to invest
// any more in it. If I ever do figure this out, I need to test the blending modes for various
// combinations of transparency, blending, and keep-non-default-background-colors-opaque settings.
// https://stackoverflow.com/questions/51354283/transparent-mtkview-not-blending-properly-with-windows-behind-it
// https://openradar.appspot.com/radar?id=4996901569036288
#define ENABLE_TRANSPARENT_METAL_WINDOWS 1

