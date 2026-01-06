//
//  iTermRestorableSession.m
//  iTerm
//
//  Created by George Nachman on 5/30/14.
//
//

#import "iTermRestorableSession.h"
#import "DebugLogging.h"
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
                                   partialAttachments:nil
                                              options:nil];
        }];
        self.terminalGuid = restorableState[@"terminalGuid"];
        self.arrangement = restorableState[@"arrangement"];
        self.predecessors = restorableState[@"predecessors"];
        self.windowType = restorableState[@"windowType"] ? [restorableState[@"windowType"] intValue] : iTermWindowDefaultType();
        if ([NSNumber castFrom:restorableState[@"percentage"]]) {
            const double p = [restorableState[@"percentage"] doubleValue];
            if (self.windowType == WINDOW_TYPE_TOP_PERCENTAGE ||
                self.windowType == WINDOW_TYPE_BOTTOM_PERCENTAGE) {
                self.percentage = (iTermPercentage){ .width = p, .height = -1 };
            } else if (self.windowType == WINDOW_TYPE_LEFT_PERCENTAGE ||
                       self.windowType == WINDOW_TYPE_RIGHT_PERCENTAGE) {
                self.percentage = (iTermPercentage){ .width = -1, .height = p };
            } else {
                self.percentage = (iTermPercentage){ .width = -1, .height = -1 };
            }
        } else if ([NSArray castFrom:restorableState[@"percentage"]]) {
            NSArray *a = restorableState[@"percentage"];
            self.percentage = (iTermPercentage){
                .width = [a[0] doubleValue],
                .height = [a[1] doubleValue]
            };
        } else {
            self.percentage = (iTermPercentage){
                .width = -1,
                .height = -1
            };
        }
        self.savedWindowType = restorableState[@"savedWindowType"] ? [restorableState[@"savedWindowType"] intValue] : iTermWindowDefaultType();
        self.screen = restorableState[@"screen"] ? [restorableState[@"screen"] intValue] : -1;
        self.windowTitle = [restorableState[@"windowTitle"] nilIfNull];
        self.channelParentGuid = [restorableState[@"channelParentGuid"] nilIfNull];
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
              @"percentage": @[ @(_percentage.width), @(_percentage.height) ],
              @"savedWindowType": @(_savedWindowType),
              @"screen": @(_screen),
              @"windowTitle": _windowTitle ?: [NSNull null],
              @"channelParentGuid": _channelParentGuid ?: [NSNull null]
    };
}

@end
