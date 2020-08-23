//
//  iTermGlobalSearchEngineCursor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import <Foundation/Foundation.h>

@class FindContext;
@class PTYSession;

NS_ASSUME_NONNULL_BEGIN

@interface iTermGlobalSearchEngineCursor: NSObject
@property (nonatomic, strong) PTYSession *session;
@property (nonatomic, strong) FindContext *findContext;
@end

NS_ASSUME_NONNULL_END
