//
//  iTermURLActionFactory.h
//  iTerm2
//
//  Created by George Nachman on 2/26/17.
//
//

#import <Foundation/Foundation.h>

#import "VT100GridTypes.h"

@class iTermTextExtractor;
@protocol iTermObject;
@class iTermSemanticHistoryController;
@class iTermVariableScope;
@class SCPPath;
@class URLAction;
@class VT100RemoteHost;

@interface iTermURLActionFactory : NSUserDefaults

+ (void)urlActionAtCoord:(VT100GridCoord)coord
     respectHardNewlines:(BOOL)respectHardNewlines
        workingDirectory:(NSString *)workingDirectory
                   scope:(iTermVariableScope *)scope
                   owner:(id<iTermObject>)owner
              remoteHost:(VT100RemoteHost *)remoteHost
               selectors:(NSDictionary<NSNumber *, NSString *> *)selectors
                   rules:(NSArray *)rules
               extractor:(iTermTextExtractor *)extractor
semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController
             pathFactory:(SCPPath *(^)(NSString *, int))pathFactory
              completion:(void (^)(URLAction *))completion;

@end
