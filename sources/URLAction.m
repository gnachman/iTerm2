//
//  URLAction.m
//  iTerm
//
//  Created by George Nachman on 12/14/13.
//
//

#import "URLAction.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermImageInfo.h"
#import "iTermSemanticHistoryController.h"
#import "iTermTextExtractor.h"
#import "NSCharacterSet+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "RegexKitLite.h"
#import "SmartSelectionController.h"
#import "SCPPath.h"

@interface URLAction ()

@property(nonatomic, copy) NSString *string;
@property(nonatomic, copy) NSDictionary *rule;
@property(nonatomic, strong) id identifier;

@end

@implementation URLAction

+ (instancetype)urlAction {
    return [[self alloc] init];
}

+ (instancetype)urlActionToSecureCopyFile:(SCPPath *)scpPath {
    URLAction *action = [self urlAction];
    action.string = scpPath.stringValue;
    action.actionType = kURLActionSecureCopyFile;
    action.identifier = scpPath;
    return action;
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
    action.actionType = kURLActionSmartSelectionAction;
    return action;
}

+ (instancetype)urlActionToOpenExistingFile:(NSString *)filename {
    URLAction *action = [self urlAction];
    action.string = filename;
    action.actionType = kURLActionOpenExistingFile;
    return action;
}

+ (instancetype)urlActionToOpenImage:(id<iTermImageInfoReading>)imageInfo {
    URLAction *action = [self urlAction];
    action.string = imageInfo.filename;
    action.actionType = kURLActionOpenImage;
    action.identifier = imageInfo;
    return action;
}

+ (instancetype)actionToShowCommandInfoForMark:(id<VT100ScreenMarkReading>)mark coord:(VT100GridCoord)coord {
    URLAction *action = [self urlAction];
    action.actionType = kURLActionShowCommandInfo;
    action.mark = mark;
    action.coord = coord;
    return action;
}

#pragma mark - NSObject

- (NSString *)description {
    NSString *actionType = @"?";
    switch (self.actionType) {
        case kURLActionOpenExistingFile:
            actionType = @"OpenExistingFile";
            break;
        case kURLActionOpenURL:
            actionType = @"OpenURL";
            break;
        case kURLActionSmartSelectionAction:
            actionType = @"SmartSelectionAction";
            break;
        case kURLActionOpenImage:
            actionType = @"OpenImage";
            break;
        case kURLActionSecureCopyFile:
            actionType = @"SecureCopyFile";
            break;
        case kURLActionShowCommandInfo:
            actionType = @"ShowCommandInfo";
            break;
    }
    return [NSString stringWithFormat:@"<%@: %p actionType=%@ string=%@ rule=%@ range=%@ coord=%@>",
            [self class], self, actionType, self.string, self.rule, VT100GridWindowedRangeDescription(_range), VT100GridCoordDescription(self.coord)];
}

@end
