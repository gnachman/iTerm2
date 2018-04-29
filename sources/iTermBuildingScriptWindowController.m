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
    __weak IBOutlet NSProgressIndicator *_progressIndicator;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [_progressIndicator startAnimation:nil];
}

@end
