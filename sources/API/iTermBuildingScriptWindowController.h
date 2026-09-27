//
//  iTermBuildingScriptWindowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermBuildingScriptWindowController : NSWindowController

// Creates the controller and orders its window front immediately.
+ (instancetype)newPleaseWaitWindowController;

// Creates the controller and positions its window but leaves it hidden when
// orderFront is NO, so a caller can defer showing it past intervening prompts
// (e.g. a replace-script or download-consent alert) and order it front later.
+ (instancetype)newPleaseWaitWindowControllerOrderingFront:(BOOL)orderFront;

@end
