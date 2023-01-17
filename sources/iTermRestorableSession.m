//
//  iTermRestorableSession.m
//  iTerm
//
//  Created by George Nachman on 5/30/14.
//
//

#import "iTermRestorableSession.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "PTYSession.h"
#import "SessionView.h"

@implementation iTermRestorableSession

- (instancetype)initWithRestorableState:(NSDictionary *)restorableState {
    self = [super init];
    if (self) {
        self.sessions = [restorableState[@"sessionFrameTuples"] mapWithBlock:^id(NSArray *tuple) {
            NSRect frame = [(NSValue *)tuple[0] rectValue];
            NSDictionary *arrangement = tuple[1];
            return [PTYSession sessionFromArrangement:arrangement
                                                named:nil
                                               inView:[[SessionView alloc] initWithFrame:frame]
                                         withDelegate:nil
                                        forObjectType:iTermPaneObject
                                   partialAttachments:nil];
        }];
        self.terminalGuid = restorableState[@"terminalGuid"];
        self.arrangement = restorableState[@"arrangement"];
        self.predecessors = restorableState[@"predecessors"];
        self.windowType = restorableState[@"windowType"] ? [restorableState[@"windowType"] intValue] : iTermWindowDefaultType();
        self.savedWindowType = restorableState[@"savedWindowType"] ? [restorableState[@"savedWindowType"] intValue] : iTermWindowDefaultType();
        self.screen = restorableState[@"screen"] ? [restorableState[@"screen"] intValue] : -1;
        self.windowTitle = [restorableState[@"windowTitle"] nilIfNull];
    }
    return self;
}

- (NSDictionary *)restorableState {
    DLog(@"Creating restorable state dictionary");
    NSArray *maybeSessionFrameTuples =
    [_sessions mapWithBlock:^id(PTYSession *session) {
        DLog(@"Encode session %@", session);
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        iTermMutableDictionaryEncoderAdapter *encoder =
            [[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:dict];
        [session encodeArrangementWithContents:YES encoder:encoder];
        return @[ [NSValue valueWithRect:session.view.frame], dict ];
    }];
    return @{ @"sessionFrameTuples": maybeSessionFrameTuples ?: @[],
              @"terminalGuid": _terminalGuid ?: @"",
              @"arrangement": _arrangement ?: @{},
              @"predecessors": _predecessors ?: @[],
              @"windowType": @(_windowType),
              @"savedWindowType": @(_savedWindowType),
              @"screen": @(_screen),
              @"windowTitle": _windowTitle ?: [NSNull null]
    };
}

@end
