//
//  iTermInitialDirectory+Tmux.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/14/19.
//

#import "iTermInitialDirectory+Tmux.h"

#import "NSStringITerm.h"

@implementation iTermInitialDirectory(Tmux)

- (void)tmuxNewWindowCommandInSession:(NSString *)session
                   recyclingSupported:(BOOL)recyclingSupported
                                scope:(iTermVariableScope *)scope
                           completion:(void (^)(NSString *))completion {
    NSArray *args = @[ @"new-window", @"-PF '#{window_id}'" ];

    if (session) {
        NSString *targetSessionArg = [NSString stringWithFormat:@"\"%@:+\"", [session stringByEscapingQuotes]];
        NSArray *insertionArguments = @[ @"-a",
                                         @"-t",
                                         targetSessionArg ];
        args = [args arrayByAddingObjectsFromArray:insertionArguments];
    }
    [self tmuxCommandByAddingCustomDirectoryWithArgs:args
                                  recyclingSupported:recyclingSupported
                                               scope:scope
                                          completion:completion];
}

- (void)tmuxNewWindowCommandRecyclingSupported:(BOOL)recyclingSupported
                                         scope:(iTermVariableScope *)scope
                                    completion:(void (^)(NSString *))completion {
    [self tmuxNewWindowCommandInSession:nil
                     recyclingSupported:recyclingSupported
                                  scope:scope
                             completion:completion];
}

- (void)tmuxSplitWindowCommand:(int)wp
                    vertically:(BOOL)splitVertically
            recyclingSupported:(BOOL)recyclingSupported
                         scope:(iTermVariableScope *)scope
                    completion:(void (^)(NSString *))completion {
    NSArray *args = @[ @"split-window",
                       splitVertically ? @"-h": @"-v",
                       @"-t",
                       [NSString stringWithFormat:@"\"%%%d\"", wp] ];
    [self tmuxCommandByAddingCustomDirectoryWithArgs:args
                                  recyclingSupported:recyclingSupported
                                               scope:scope
                                          completion:completion];
}

- (void)tmuxCustomDirectoryParameterRecyclingSupported:(BOOL)recyclingSupported
                                                 scope:(iTermVariableScope *)scope
                                            completion:(void (^)(NSString *))completion {
    switch (self.mode) {
        case iTermInitialDirectoryModeHome:
            completion(nil);
            return;
        case iTermInitialDirectoryModeCustom:
            break;
        case iTermInitialDirectoryModeRecycle:
            if (recyclingSupported) {
                completion(@"#{pane_current_path}");
                return;
            } else {
                completion(nil);
                return;
            }
    }
    // Custom
    [self evaluateWithOldPWD:nil
                       scope:scope
                 synchronous:NO
                  completion:
     ^(NSString *result) {
         NSString *escaped = [result stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
         completion(escaped);
     }];
}

- (void)tmuxCommandByAddingCustomDirectoryWithArgs:(NSArray *)defaultArgs
                                recyclingSupported:(BOOL)recyclingSupported
                                             scope:(iTermVariableScope *)scope
                                        completion:(void (^)(NSString *))completion {
    [self tmuxCustomDirectoryParameterRecyclingSupported:recyclingSupported
                                                   scope:scope
                                              completion:
     ^(NSString *result) {
         NSArray *args = defaultArgs;
         NSString *customDirectory = result;
         if (customDirectory) {
             NSString *escapedCustomDirectory= [customDirectory stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
             NSString *customDirectoryArgument = [NSString stringWithFormat:@"-c '%@'", escapedCustomDirectory];
             args = [args arrayByAddingObject:customDirectoryArgument];
         }
         completion([args componentsJoinedByString:@" "]);
     }];
}

@end

