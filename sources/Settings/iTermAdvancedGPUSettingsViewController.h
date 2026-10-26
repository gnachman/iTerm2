//
//  iTermAdvancedGPUSettingsViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/18/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermAdvancedGPUSettingsViewController : NSViewController

@property (nonatomic, strong) IBOutlet NSButton *disableWhenDisconnected;
@property (nonatomic, strong) IBOutlet NSButton *disableInLowPowerMode;
@property (nonatomic, strong) IBOutlet NSButton *preferIntegratedGPU;

// YES if this Mac has both an integrated (low power) and a discrete GPU, so preferring the
// integrated one is a real choice.
+ (BOOL)canPreferIntegratedGPU;

// Same, given each GPU's isLowPower value.
+ (BOOL)canPreferIntegratedGPUWithLowPowerFlags:(NSArray<NSNumber *> *)lowPowerFlags;

@end

@interface iTermAdvancedGPUSettingsWindowController : NSWindowController
@property (nonatomic, strong) IBOutlet iTermAdvancedGPUSettingsViewController *viewController;
@end
