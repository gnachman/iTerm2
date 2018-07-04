//
//  iTermAdvancedGPUSettingsViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/18/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermAdvancedGPUSettingsViewController : NSViewController

@property (nonatomic, strong) IBOutlet NSButton *disableWhenDisconnected;
@property (nonatomic, strong) IBOutlet NSButton *preferIntegratedGPU;
@property (nonatomic, strong) IBOutlet NSButton *maximizeThroughput;

@end

@interface iTermAdvancedGPUSettingsWindowController : NSWindowController
@property (nonatomic, strong) IBOutlet iTermAdvancedGPUSettingsViewController *viewController;
@end
