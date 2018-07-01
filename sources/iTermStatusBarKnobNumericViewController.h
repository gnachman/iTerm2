//
//  iTermStatusBarKnobNumericViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarComponentKnob.h"

@interface iTermStatusBarKnobNumericViewController : NSViewController<iTermStatusBarKnobViewController>

@property (nonatomic, strong) IBOutlet NSTextField *label;
@property (nonatomic, strong) IBOutlet NSTextField *textField;
@property (nonatomic, strong) IBOutlet NSStepper *stepper;
@property (nonatomic) NSNumber *value;

@end
