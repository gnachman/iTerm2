//
//  ToolWrapper.h
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ToolbeltView.h"

@class PseudoTerminal;

@interface ToolWrapper : NSView {
    NSTextField *title_;
    NSButton *closeButton_;
    NSString *name;
    NSView *container_;
    PseudoTerminal *term;
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) NSView *container;
@property (nonatomic, assign) PseudoTerminal *term;

- (void)relayout;
- (void)bindCloseButton;
- (void)unbind;
- (NSObject<ToolbeltTool> *)tool;

@end
