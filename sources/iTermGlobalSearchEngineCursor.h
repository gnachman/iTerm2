//
//  iTermGlobalSearchEngineCursor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import <Foundation/Foundation.h>
#import "iTermFindViewController.h"

@class FindContext;
@class PTYSession;
@class iTermSearchEngine;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermGlobalSearchEngineCursorPass) {
    iTermGlobalSearchEngineCursorPassMainScreen,
    iTermGlobalSearchEngineCursorPassCurrentScreen
};

@interface iTermGlobalSearchEngineCursor: NSObject
@property (nonatomic, strong) PTYSession *session;
@property (nonatomic, strong) iTermSearchEngine *searchEngine;
@property (nonatomic) iTermGlobalSearchEngineCursorPass pass;
@property (nonatomic, copy) NSString *query;
@property (nonatomic) iTermFindMode mode;
@property (nonatomic) BOOL currentScreenIsAlternate;
@end

NS_ASSUME_NONNULL_END
