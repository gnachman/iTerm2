//
//  iTermSerializableImage.h
//  iTerm2
//
//  Created by George Nachman on 8/28/16.
//
//

#import <Cocoa/Cocoa.h>

// Represents an image, possibly animated, that can be converted to JSON.
@interface iTermSerializableImage : NSObject

// Either empty or 1:1 with images.
@property(nonatomic) NSMutableArray<NSNumber *> *delays;
@property(nonatomic) NSSize size;
@property(nonatomic) NSMutableArray<NSImage *> *images;

- (NSData *)jsonValue;

@end
