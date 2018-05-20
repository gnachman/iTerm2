//
//  iTermFunctionCallTextFieldDelegate.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermFunctionCallTextFieldDelegate : NSObject<NSTextFieldDelegate>

@property (nonatomic, strong) IBOutlet NSTextField *textField;

@end
