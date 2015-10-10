//
//  HighlightTrigger.h
//  iTerm2
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "Trigger.h"

@interface HighlightTrigger : Trigger

+ (NSString *)title;
@property (readonly) BOOL takesParameter;
@property (readonly) BOOL paramIsPopupButton;

@end
