//
//  TextViewWrapper.h
//  iTerm
//
//  Created by George Nachman on 11/14/10.
//  Copyright 2010 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PTYTextView;
@interface TextViewWrapper : NSView {
	PTYTextView* child_;
}

- (void)addSubview:(PTYTextView*)child;
- (NSRect)adjustScroll:(NSRect)proposedVisibleRect;

@end
