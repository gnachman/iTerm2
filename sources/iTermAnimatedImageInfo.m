//
//  iTermAnimatedImageInfo.m
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import "iTermAnimatedImageInfo.h"
#import "iTermImage.h"

@implementation iTermAnimatedImageInfo {
    iTermImage *_image;
    NSTimeInterval _creationTime;
    NSTimeInterval _maxDelay;
    int _lastFrameNumber;
}

- (instancetype)initWithImage:(iTermImage *)image {
    if (!image || image.delays.count == 0) {
        // Not animated or no image available.
        return nil;
    }
    self = [super init];
    if (self) {
        _image = [image retain];
        _maxDelay = [_image.delays.lastObject doubleValue];
        _creationTime = [NSDate timeIntervalSinceReferenceDate];
    }
    return self;
}

- (void)dealloc {
    [_image release];
    [super dealloc];
}

- (void)setPaused:(BOOL)paused {
    _paused = paused;
}

- (int)currentFrame {
    if (_paused) {
        return _lastFrameNumber;
    }
    NSTimeInterval offset = [NSDate timeIntervalSinceReferenceDate] - _creationTime;
    NSTimeInterval delay = fmod(offset, _maxDelay);
    for (int i = 0; i < _image.delays.count; i++) {
        if ([_image.delays[i] doubleValue] >= delay) {
            _lastFrameNumber = i;
            return i;
        }
    }
    _lastFrameNumber = 0;
    return 0;
}

- (NSImage *)currentImage {
    return _image.images[self.currentFrame];
}

- (NSImage *)imageForFrame:(int)frame {
    return _image.images[frame];
}

@end
