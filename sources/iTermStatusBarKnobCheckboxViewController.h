//
//  iTermStatusBarKnobCheckboxViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarComponentKnob.h"

@interface iTermStatusBarKnobCheckboxViewController : NSViewController<iTermStatusBarKnobViewController>

@property (nonatomic, strong) IBOutlet NSButton *checkbox;
@property (nonatomic) NSNumber *value;

@end
