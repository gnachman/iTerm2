//
//  iTermMenuOpener.h
//  iTerm2
//
//  Created by George Nachman on 3/6/17.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermMenuOpener : NSObject

+ (void)revealMenuWithPath:(NSArray<NSString *> *)path
                   message:(NSString *)message;

@end
