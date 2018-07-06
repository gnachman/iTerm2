//
//  iTermStatusBarKnobColorViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/5/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarComponentKnob.h"
#import <ColorPicker/ColorPicker.h>

@interface iTermStatusBarKnobColorViewController : NSViewController<iTermStatusBarKnobViewController>

@property (nonatomic, strong) IBOutlet NSTextField *label;
@property (nonatomic) NSDictionary *value;

@end
