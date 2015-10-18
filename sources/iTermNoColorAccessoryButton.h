//
//  iTermNoColorAccessoryButton.h
//  iTerm2
//
//  Created by George Nachman on 6/5/15.
//
//

#import <Cocoa/Cocoa.h>

// First responders may implement methods in this protocol.
@protocol iTermNoColorAccessoryButtonResponder <NSObject>
@optional
- (void)noColorChosen:(id)sender;
@end

// A button for use as an accessory in the color picker panel that selects "no color".
@interface iTermNoColorAccessoryButton : NSButton
@end
