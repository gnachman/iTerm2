//
//  iTermAdjustFontSizeHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/16/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PTYSession;

@interface iTermAdjustFontSizeHelper : NSObject

+ (void)biggerFont:(PTYSession *)currentSession;
+ (void)smallerFont:(PTYSession *)currentSession;
+ (void)returnToDefaultSize:(PTYSession *)currentSession
              resetRowsCols:(BOOL)reset;
+ (void)toggleSizeChangesAffectProfile;

@end

NS_ASSUME_NONNULL_END
