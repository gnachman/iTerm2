//
//  iTermAdvancedGPUSettingsViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/18/18.
//

#import "iTermAdvancedGPUSettingsViewController.h"

#import <Metal/Metal.h>

@interface iTermAdvancedGPUSettingsViewController ()

@end

@implementation iTermAdvancedGPUSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();

    BOOL foundLowPower = NO;
    BOOL foundHighPower = NO;
    for (id<MTLDevice> device in devices) {
        if (device.isLowPower) {
            foundLowPower = YES;
        } else {
            foundHighPower = YES;
        }
    }

    self.preferIntegratedGPU.enabled = (foundLowPower && foundHighPower);
    if (@available(macOS 12.0, *)) {
        self.disableInLowPowerMode.enabled = YES;
    } else {
        self.disableInLowPowerMode.enabled = NO;
    }
}

@end

@implementation iTermAdvancedGPUSettingsWindowController

- (IBAction)ok:(id)sender {
    [self.window.sheetParent endSheet:self.window
                           returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [self.window.sheetParent endSheet:self.window
                           returnCode:NSModalResponseCancel];
}

@end

