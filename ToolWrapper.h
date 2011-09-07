//
//  ToolWrapper.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PseudoTerminal;

@interface ToolWrapper : NSView {
    NSTextField *title_;
    NSButton *closeButton_;
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) NSView *container;
@property (nonatomic, assign) PseudoTerminal *term;

- (void)bindCloseButton;
- (void)unbind;

@end
