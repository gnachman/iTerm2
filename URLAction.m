//
//  URLAction.m
//  iTerm
//
//  Created by George Nachman on 12/14/13.
//
//

#import "URLAction.h"

@interface URLAction ()

@property(nonatomic, copy) NSString *string;
@property(nonatomic, copy) NSDictionary *rule;

@end

@implementation URLAction

+ (instancetype)urlAction {
    return [[[self alloc] init] autorelease];
}

+ (instancetype)urlActionToOpenURL:(NSString *)filename {
    URLAction *action = [self urlAction];
    action.string = filename;
    action.actionType = kURLActionOpenURL;
    return action;
}

+ (instancetype)urlActionToPerformSmartSelectionRule:(NSDictionary *)rule
                                            onString:(NSString *)content {
    URLAction *action = [self urlAction];
    action.string = content;
    action.rule = rule;
    action.actionType = kURLActionSmartSelectionAction;;
    return action;
}

+ (instancetype)urlActionToOpenExistingFile:(NSString *)filename {
    URLAction *action = [self urlAction];
    action.string = filename;
    action.actionType = kURLActionOpenExistingFile;
    return action;
}

- (void)dealloc {
    [_string release];
    [_rule release];
    [_fullPath release];
    [_workingDirectory release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p string=%@ rule=%@>",
            [self class], self, self.string, self.rule];
}

@end
