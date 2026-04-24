//
//  iTermParameterPanelWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/3/18.
//

#import "iTermParameterPanelWindowController.h"

@interface iTermParameterPanelWindowController ()

@end

@implementation iTermParameterPanelWindowController

// Called when the parameter panel should close.
- (IBAction)parameterPanelEnd:(id)sender {
    _canceled = ([sender tag] == 0);
    [NSApp stopModal];
}

@end
