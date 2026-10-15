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

+ (BOOL)canPreferIntegratedGPU {
    NSMutableArray<NSNumber *> *flags = [NSMutableArray array];
    for (id<MTLDevice> device in MTLCopyAllDevices()) {
        [flags addObject:@(device.isLowPower)];
    }
    return [self canPreferIntegratedGPUWithLowPowerFlags:flags];
}

+ (BOOL)canPreferIntegratedGPUWithLowPowerFlags:(NSArray<NSNumber *> *)lowPowerFlags {
    BOOL foundLowPower = NO;
    BOOL foundHighPower = NO;
    for (NSNumber *lowPower in lowPowerFlags) {
        if (lowPower.boolValue) {
            foundLowPower = YES;
        } else {
            foundHighPower = YES;
        }
    }
    return foundLowPower && foundHighPower;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.preferIntegratedGPU.enabled = [iTermAdvancedGPUSettingsViewController canPreferIntegratedGPU];
    self.disableInLowPowerMode.enabled = YES;
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

