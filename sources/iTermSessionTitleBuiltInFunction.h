//
//  iTermSessionTitleBuiltInFunction.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/19/18.
//

#import <Foundation/Foundation.h>

#import "ITAddressBookMgr.h"
#import "iTermBuiltInFunctions.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermSessionTitleBuiltInFunction : NSObject<iTermBuiltInFunction>

+ (NSString *)titleForSessionName:(NSString *)sessionName
                      profileName:(NSString *)profileName
                              job:(NSString *)jobVariable
                              pwd:(NSString *)pwdVariable
                              tty:(NSString *)ttyVariable
                             user:(NSString *)userVariable
                             host:(NSString *)hostVariable
                             tmux:(nullable NSString *)tmuxVariable
                         iconName:(NSString *)iconName
                       windowName:(NSString *)windowName
                       components:(iTermTitleComponents)titleComponents;


@end

NS_ASSUME_NONNULL_END
