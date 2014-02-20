//
//  URLAction.h
//  iTerm
//
//  Created by George Nachman on 12/14/13.
//
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

typedef enum {
    kURLActionOpenURL,
    kURLActionSmartSelectionAction,
    kURLActionOpenExistingFile
} URLActionType;

@interface URLAction : NSObject

// Always set.
@property(nonatomic, assign) URLActionType actionType;

// Always set. Generally, the text that was used to select the action (e.g., the selection).
@property(nonatomic, readonly) NSString *string;

// Always set. The range of |string| on screen.
@property(nonatomic, assign) VT100GridWindowedRange range;

// For kURLActionOpenExistingFile, the full path the the file.
@property(nonatomic, copy) NSString *fullPath;

// For kURLActionOpenExistingFile, the working directory of the file.
@property(nonatomic, copy) NSString *workingDirectory;

// For kURLActionSmartSelectionAction, the rule used.
@property(nonatomic, readonly) NSDictionary *rule;

// For kURLActionSmartSelectionAction. Generally, a string parameter to a smart
// selection action.
@property(nonatomic, retain) id representedObject;

// For kURLActionSmartSelectionAction, the selector to invoke. This URLAction
// will be passed as the argument.
@property(nonatomic, assign) SEL selector;

+ (instancetype)urlActionToOpenURL:(NSString *)filename;
+ (instancetype)urlActionToPerformSmartSelectionRule:(NSDictionary *)rule
                                            onString:(NSString *)content;
+ (instancetype)urlActionToOpenExistingFile:(NSString *)filename;

@end
