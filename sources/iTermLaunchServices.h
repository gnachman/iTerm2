//
//  iTermLaunchServices.h
//  iTerm2
//
//  Created by George Nachman on 1/6/16.
//
//

#import <Foundation/Foundation.h>

@interface iTermLaunchServices : NSObject

+ (void)makeITermDefaultTerminal;
+ (void)makeTerminalDefaultTerminal;
+ (BOOL)iTermIsDefaultTerminal;

@end
