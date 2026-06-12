//
//  iTermImage+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/27/20.
//

@interface iTermImage ()
// Actual bitmap size
@property (nonatomic, readwrite) NSSize size;

// Size of NSImage. Use this for source rects.
@property (nonatomic, readwrite) NSSize scaledSize;
@end
