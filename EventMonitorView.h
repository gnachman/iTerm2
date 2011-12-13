//
//  EventMonitorView.h
//  iTerm
//
//  Created by George Nachman on 11/9/11.
//  Copyright (c) 2011 George Nachman. All rights reserved.
//
//  Pass clicks and taps in a view to PointerPrefsController to set
//  button/gesture, num clicks, and modifiers.

#import <Cocoa/Cocoa.h>

@class PointerPrefsController;

@interface EventMonitorView : NSView {
    IBOutlet PointerPrefsController *pointerPrefs_;
    IBOutlet NSTextField *label_;
    int numTouches_;
}

@end
