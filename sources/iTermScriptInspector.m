//
//  iTermScriptInspector.m
//  iTerm2
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermScriptInspector.h"
#import "iTermSessionTabWindowOutlineDelegate.h"
#import "iTermRegisteredFunctionsTableViewDelegate.h"

@interface iTermScriptInspector ()

@end

@implementation iTermScriptInspector {
    IBOutlet iTermSessionTabWindowOutlineDelegate *_sessionTabWindowOutlineDelegate;
    IBOutlet iTermRegisteredFunctionsTableViewDelegate *_registeredFunctionTableViewDelegate;
}

- (IBAction)reload:(id)sender {
    [_sessionTabWindowOutlineDelegate reload];
    [_registeredFunctionTableViewDelegate reload];
}

- (IBAction)closeCurrentSession:(id)sender {
    [self close];
}

@end
