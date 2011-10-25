//
//  PseudoTerminalRestorer.m
//  iTerm
//
//  Created by George Nachman on 10/24/11.
//

#import "PseudoTerminalRestorer.h"
#import "PseudoTerminal.h"
#import "iTermController.h"

@implementation PseudoTerminalRestorer

+ (void)restoreWindowWithIdentifier:(NSString *)identifier
                              state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
    NSDictionary *arrangement = [state decodeObjectForKey:@"ptyarrangement"];
    if (arrangement) {
        PseudoTerminal *term = [PseudoTerminal bareTerminalWithArrangement:arrangement];
        completionHandler([term window], nil);
        [[iTermController sharedInstance] addInTerminals:term];
    } else {
        completionHandler(nil, nil);
    }
}

@end
