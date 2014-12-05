//
//  AMIndeterminateProgressIndicator.h
//
//  Created by Andreas on 23.01.07.
//  Copyright 2007 Andreas Mayer. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface AMIndeterminateProgressIndicator : NSView

@property(nonatomic, retain) NSColor *color;

- (void)startAnimation:(id)sender;
- (void)stopAnimation:(id)sender;


@end
