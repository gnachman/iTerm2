//
//  iTermImageMark.m
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import "iTermImageMark.h"
#import "ScreenChar.h"

@implementation iTermImageMark

- (void)dealloc {
    if (_imageCode) {
        ReleaseImage(_imageCode.integerValue);
        [_imageCode release];
    }
    [super dealloc];
}

@end
