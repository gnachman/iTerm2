//
//  iTermCacheableImage.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/18.
//

#import "iTermCacheableImage.h"
#import "NSImage+iTerm.h"

@implementation iTermCacheableImage {
    NSString *_path;
    NSImage *_image;
    NSSize _size;
    BOOL _flipped;
}

- (NSImage *)imageAtPath:(NSString *)path ofSize:(NSSize)size flipped:(BOOL)flipped {
    if (_image &&
        path &&
        _path &&
        [path isEqualToString:_path] &&
        NSEqualSizes(size, _size) &&
        flipped == _flipped) {
        return _image;
    }

    _path = [path copy];
    _size = size;
    _flipped = flipped;

    _image = [[NSImage alloc] initWithContentsOfFile:path];
    if (flipped) {
        _image = [_image it_flippedImage];
    }
    if (!NSEqualSizes(size, _image.size)) {
        _image = [_image it_imageOfSize:size];
    }
    return _image;
}

@end
