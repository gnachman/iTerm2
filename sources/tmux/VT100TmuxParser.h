//
//  VT100TmuxParser.h
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"
#import "iTermParser.h"
#import "VT100DCSParser.h"

@interface VT100TmuxParser : NSObject <VT100DCSParserHook>
- (instancetype)initInRecoveryMode;
@end
