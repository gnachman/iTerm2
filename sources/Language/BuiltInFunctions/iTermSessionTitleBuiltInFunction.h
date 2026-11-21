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

// Abbreviates a home-directory prefix in an absolute path to "~". Boundary-correct:
// only rewrites when the path equals home or begins with home + "/", and a root home
// "/" is left as no-op. The single shared implementation (the AI-title context uses it
// too).
+ (NSString *)prettyPWD:(nullable NSString *)absolutePath
          homeDirectory:(nullable NSString *)home;

+ (NSString *)titleForSessionName:(nullable NSString *)sessionName
                      profileName:(nullable NSString *)profileName
                              job:(nullable NSString *)jobVariable
                      commandLine:(nullable NSString *)commandLineVariable
                              pwd:(nullable NSString *)pwdVariable
                              tty:(nullable NSString *)ttyVariable
                             user:(nullable NSString *)userVariable
                             host:(nullable NSString *)hostVariable
                          aiTitle:(nullable NSString *)aiTitleVariable
                    homeDirectory:(nullable NSString *)homeDirectory
                         tmuxPane:(nullable NSString *)tmuxPaneVariable
                         iconName:(nullable NSString *)iconName
                       windowName:(nullable NSString *)windowName
                   tmuxWindowName:(nullable NSString *)tmuxWindowName
                  tmuxWindowTitle:(nullable NSString *)tmuxWindowTitle
                             rows:(nullable NSNumber *)rows
                          columns:(nullable NSNumber *)columns
                       components:(iTermTitleComponents)titleComponents
                    isWindowTitle:(BOOL)isWindowTitle;


@end

NSString *iTermColumnsByRowsString(int columns, int rows);

NS_ASSUME_NONNULL_END
