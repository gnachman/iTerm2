//
//  iTermBuildingScriptWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import "iTermBuildingScriptWindowController.h"

@interface iTermBuildingScriptWindowController ()

@end

@implementation iTermBuildingScriptWindowController {
    IBOutlet NSProgressIndicator *_progressIndicator;
}

+ (instancetype)newPleaseWaitWindowController {
    iTermBuildingScriptWindowController *pleaseWait = [[self alloc] initWithWindowNibName:@"iTermBuildingScriptWindowController"];
    pleaseWait.window.alphaValue = 0;
    NSScreen *screen = pleaseWait.window.screen;
    NSRect screenFrame = screen.frame;
    NSSize windowSize = pleaseWait.window.frame.size;
    NSPoint screenCenter = NSMakePoint(NSMinX(screenFrame) + NSWidth(screenFrame) / 2,
                                       NSMinY(screenFrame) + NSHeight(screenFrame) / 2);
    NSPoint windowOrigin = NSMakePoint(screenCenter.x - windowSize.width / 2,
                                       screenCenter.y - windowSize.height / 2);
    [pleaseWait.window setFrameOrigin:windowOrigin];
    pleaseWait.window.alphaValue = 1;

    [pleaseWait.window makeKeyAndOrderFront:nil];
    return pleaseWait;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [_progressIndicator startAnimation:nil];
}

@end
