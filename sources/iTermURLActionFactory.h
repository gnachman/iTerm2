//
//  iTermURLActionFactory.h
//  iTerm2
//
//  Created by George Nachman on 2/26/17.
//
//

#import <Foundation/Foundation.h>

#import "VT100GridTypes.h"
#import "iTermCancelable.h"

@class iTermTextExtractor;
@protocol iTermObject;
@class iTermSemanticHistoryController;
@class iTermVariableScope;
@class SCPPath;
@class URLAction;
@protocol VT100RemoteHostReading;

@interface iTermURLActionFactory : NSUserDefaults<iTermCancelable>

+ (instancetype)urlActionAtCoord:(VT100GridCoord)coord
             respectHardNewlines:(BOOL)respectHardNewlines
                       alternate:(BOOL)alternate
                workingDirectory:(NSString *)workingDirectory
                           scope:(iTermVariableScope *)scope
                           owner:(id<iTermObject>)owner
                      remoteHost:(id<VT100RemoteHostReading>)remoteHost
                       selectors:(NSDictionary<NSNumber *, NSString *> *)selectors
                           rules:(NSArray *)rules
                       extractor:(iTermTextExtractor *)extractor
       semanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController
                     pathFactory:(SCPPath *(^)(NSString *, int))pathFactory
                      completion:(void (^)(URLAction *))completion;

@end
