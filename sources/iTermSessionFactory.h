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

// pass self.disablePromptForSubstitutions for promptingDisabled
- (NSDictionary *)substitutionsForCommand:(NSString *)command
                              sessionName:(NSString *)name
                        baseSubstitutions:(NSDictionary *)substitutions
                                canPrompt:(BOOL)canPrompt
                                   window:(NSWindow *)window;

- (BOOL)attachOrLaunchCommandInSession:(PTYSession *)aSession
                             canPrompt:(BOOL)canPrompt
                            objectType:(iTermObjectType)objectType
                      serverConnection:(iTermFileDescriptorServerConnection * _Nullable)serverConnection
                             urlString:(nullable NSString *)urlString
                          allowURLSubs:(BOOL)allowURLSubs
                                oldCWD:(nullable NSString *)oldCWD
                      windowController:(PseudoTerminal * _Nonnull)windowController;
@end

NS_ASSUME_NONNULL_END
