//
//  InteractiveScriptTrigger.h
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ScriptTrigger.h"


@interface CoprocessTrigger : Trigger

+ (NSString *)title;

@end

@interface MuteCoprocessTrigger : CoprocessTrigger

+ (NSString *)title;

@end
