//
//  iTermScriptChooser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import <Cocoa/Cocoa.h>

@class SIGIdentity;

@interface iTermScriptChooser : NSObject

+ (void)chooseWithValidator:(BOOL (^)(NSURL *))validator
                 completion:(void (^)(NSURL *, SIGIdentity *))completion;

@end
