//
//  iTermPrintAccessoryViewController.h
//  iTerm2
//
//  Created by George Nachman on 11/19/15.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermPrintAccessoryViewController : NSViewController<NSPrintPanelAccessorizing>

// Has a Cocoa binding in interface builder to the checkbox.
@property(nonatomic, assign) BOOL blackAndWhite;

// Called when any property here changes.
@property (nonatomic, copy) void (^userDidChangeSetting)();

@end
