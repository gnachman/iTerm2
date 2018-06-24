//
//  iTermScriptChooser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermScriptChooser : NSObject

+ (void)chooseWithValidator:(BOOL (^)(NSURL *))validator
                 completion:(void (^)(NSURL *))completion;

@end
