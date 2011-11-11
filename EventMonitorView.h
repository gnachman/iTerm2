//
//  EventMonitorView.h
//  iTerm
//
//  Created by George Nachman on 11/9/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PointerPrefsController;

@interface EventMonitorView : NSView {
    IBOutlet PointerPrefsController *pointerPrefs_;
    IBOutlet NSTextField *label_;
    int numTouches_;
}

@end
