//
//  iTermMetalConfig.h
//  iTerm2
//
//  Created by George Nachman on 3/30/18.
//

#define ENABLE_PER_FRAME_METAL_STATS 0

// Sometimes when you ask MKTView for its currentDrawable, you get back a drawable with a texture
// that you've never seen before. When you go to presentDrawable:, the completion handler is called
// but it never becomes visible! This flag enables a workaround where we redraw any frame with a
// never-before-seen texture. I have a question out to developer tech support on this one.
#define ENABLE_UNFAMILIAR_TEXTURE_WORKAROUND 1
