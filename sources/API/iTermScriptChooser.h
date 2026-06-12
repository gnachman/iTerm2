//
//  iTermScriptChooser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import <Cocoa/Cocoa.h>

@class SIGIdentity;

@interface iTermScriptChooser : NSObject

+ (void)chooseMultipleWithValidator:(BOOL (^)(NSURL *))validator
                autoLaunchByDefault:(BOOL)autoLaunchByDefault
                         completion:(void (^)(NSArray<NSURL *> *,
                                              SIGIdentity *,
                                              BOOL autolaunch))completion;

@end
