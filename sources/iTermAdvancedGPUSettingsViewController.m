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
}

@end
