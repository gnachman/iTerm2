//
//  HighlightTrigger.h
//  iTerm2
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "Trigger.h"

@interface HighlightTrigger : Trigger

@property(nonatomic, readonly) BOOL takesParameter;
@property(nonatomic, readonly) BOOL paramIsPopupButton;

+ (NSString *)title;

@end
