//
//  NSImageView+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import "NSImageView+iTerm.h"
#import "NSImage+iTerm.h"

@implementation NSImageView (iTerm)

- (void)it_setTintColor:(NSColor *)color {
    if (@available(macOS 10.14, *)) {
        self.contentTintColor = color;
        return;
    }

    self.image = [self.image it_imageWithTintColor:color];
}

@end
