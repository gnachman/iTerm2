//
//  iTermMetalConfig.h
//  iTerm2
//
//  Created by George Nachman on 3/30/18.
//

// Perform most metal activities on a private queue? Relieves the main thread of most drawing
// work when enabled.
#define ENABLE_PRIVATE_QUEUE 1

// It's not clear to me if dispatching to the main queue is actually necessary, but I'm leaving
// this here so it's easy to switch back to doing so. It adds a ton of latency when enabled.
#define ENABLE_DISPATCH_TO_MAIN_QUEUE_FOR_ENQUEUEING_DRAW_CALLS 0

#define ENABLE_PER_FRAME_METAL_STATS 0
#define ENABLE_STATS 1

// This is not 100% baked, but since the OS appears to be busted I'm not going to invest
// any more in it. If I ever do figure this out, I need to test the blending modes for various
// combinations of transparency, blending, and keep-non-default-background-colors-opaque settings.
// https://stackoverflow.com/questions/51354283/transparent-mtkview-not-blending-properly-with-windows-behind-it
// https://openradar.appspot.com/radar?id=4996901569036288
#define ENABLE_TRANSPARENT_METAL_WINDOWS 1

// Sometimes when you ask MKTView for its currentDrawable, you get back a drawable with a texture
// that you've never seen before. When you go to presentDrawable:, the completion handler is called
// but it never becomes visible! This flag enables a workaround where we redraw any frame with a
// never-before-seen texture. I have a question out to developer tech support on this one.
#define ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND 1

// Disable metal renderer when there's a subview like a porthole or annotation?
#define ENABLE_FORCE_LEGACY_RENDERER_WITH_PTYTEXTVIEW_SUBVIEWS 0
