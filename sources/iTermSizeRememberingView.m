//
//  iTermSizeRememberingView.m
//  iTerm
//
//  Created by George Nachman on 6/23/14.
//
//

#import "iTermSizeRememberingView.h"

@implementation iTermSizeRememberingView {
  NSSize _originalSize;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _originalSize = frame.size;
    }
    return self;
}

- (void)awakeFromNib {
    if (NSEqualSizes(NSZeroSize, _originalSize)) {
        _originalSize = self.frame.size;
    }
}

- (void)resetToOriginalSize {
    [self setFrameSize:_originalSize];
}

@end

@implementation iTermPrefsProfilesGeneralView
@end
