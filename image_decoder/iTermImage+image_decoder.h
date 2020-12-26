//
//  iTermImage+image_decoder.h
//  iTerm2
//
//  Created by George Nachman on 8/28/16.
//
//

#import <Cocoa/Cocoa.h>

// Represents an image, possibly animated, that can be encoded.
// Has to be the same class name as in the main app for NSSecureCoding.
@interface iTermImage : NSObject <NSSecureCoding>

// Either empty or 1:1 with images.
@property(nonatomic) NSMutableArray<NSNumber *> *delays;
@property(nonatomic) NSSize size;
@property(nonatomic) NSMutableArray<NSImage *> *images;

@end
