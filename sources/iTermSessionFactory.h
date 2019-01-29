//
//  iTermSessionFactory.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/3/18.
//

#import <Foundation/Foundation.h>

#import "ITAddressBookMgr.h"
#import "iTermFileDescriptorClient.h"

NS_ASSUME_NONNULL_BEGIN

@class PTYSession;
@class Profile;
@class PseudoTerminal;

@interface iTermSessionFactory : NSObject

@property (nonatomic) BOOL promptingDisabled;

- (PTYSession *)newSessionWithProfile:(Profile *)profile;

- (BOOL)attachOrLaunchCommandInSession:(PTYSession *)aSession
                             canPrompt:(BOOL)canPrompt
                            objectType:(iTermObjectType)objectType
                      serverConnection:(iTermFileDescriptorServerConnection * _Nullable)serverConnection
                             urlString:(nullable NSString *)urlString
                          allowURLSubs:(BOOL)allowURLSubs
                           environment:(nullable NSDictionary *)environment
                                oldCWD:(nullable NSString *)oldCWD
                        forceUseOldCWD:(BOOL)forceUseOldCWD  // Change custom directory setting to make it use the passed-in oLDCWD
                               command:(nullable NSString *)command   // Overrides profile's command if nonnil
                                isUTF8:(nullable NSNumber *)isUTF8Number // Overrides profile's iSUTF8 if nonnil
                         substitutions:(nullable NSDictionary *)substitutions
                      windowController:(PseudoTerminal * _Nonnull)windowController
                            completion:(void (^ _Nullable)(BOOL))completion;  // If nonnil this may be async
@end

NS_ASSUME_NONNULL_END
