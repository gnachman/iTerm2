//
//  ArrangementPreviewView.h
//  iTerm
//
//  Created by George Nachman on 8/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface ArrangementPreviewView : NSView {
    NSArray *arrangement_;
}

- (void)setArrangement:(NSArray*)arrangement;

- (void)drawRect:(NSRect)rect;

@end
