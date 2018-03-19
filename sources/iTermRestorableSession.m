//
//  iTermRestorableSession.m
//  iTerm
//
//  Created by George Nachman on 5/30/14.
//
//

#import "iTermRestorableSession.h"
#import "NSArray+iTerm.h"
#import "PTYSession.h"
#import "SessionView.h"

@implementation iTermRestorableSession

- (void)dealloc {
    [_sessions release];
    [_terminalGuid release];
    [_arrangement release];
    [_predecessors release];
    [super dealloc];
}

- (instancetype)initWithRestorableState:(NSDictionary *)restorableState {
    self = [super init];
    if (self) {
        self.sessions = [restorableState[@"sessionFrameTuples"] mapWithBlock:^id(NSArray *tuple) {
            NSRect frame = [(NSValue *)tuple[0] rectValue];
            NSDictionary *arrangement = tuple[1];
            return [PTYSession sessionFromArrangement:arrangement inView:[[[SessionView alloc] initWithFrame:frame] autorelease] withDelegate:nil forObjectType:iTermPaneObject];
        }];
        self.terminalGuid = restorableState[@"terminalGuid"];
        self.arrangement = restorableState[@"arrangement"];
        self.predecessors = restorableState[@"predecessors"];
        self.windowType = restorableState[@"windowType"] ? [restorableState[@"windowType"] intValue] : WINDOW_TYPE_NORMAL;
        self.savedWindowType = restorableState[@"savedWindowType"] ? [restorableState[@"savedWindowType"] intValue] : WINDOW_TYPE_NORMAL;
        self.screen = restorableState[@"screen"] ? [restorableState[@"screen"] intValue] : -1;
    }
    return self;
}

- (NSDictionary *)restorableState {
    return @{ @"sessionFrameTuples": [_sessions mapWithBlock:^id(PTYSession *session) { return @[ [NSValue valueWithRect:session.view.frame], [session arrangementWithContents:YES] ]; }] ?: @[],
              @"terminalGuid": _terminalGuid ?: @"",
              @"arrangement": _arrangement ?: @{},
              @"predecessors": _predecessors ?: @[],
              @"windowType": @(_windowType),
              @"savedWindowType": @(_savedWindowType),
              @"screen": @(_screen) };
}

@end
