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
- (PTYSession *)createSessionWithProfile:(NSDictionary *)profile
                                 withURL:(nullable NSString *)urlString
                           forObjectType:(iTermObjectType)objectType
                        serverConnection:(nullable iTermFileDescriptorServerConnection *)serverConnection
                               canPrompt:(BOOL)canPrompt
                        windowController:(PseudoTerminal *)windowController;

// pass self.disablePromptForSubstitutions for promptingDisabled
- (NSDictionary *)substitutionsForCommand:(NSString *)command
                              sessionName:(NSString *)name
                        baseSubstitutions:(NSDictionary *)substitutions
                                canPrompt:(BOOL)canPrompt
                                   window:(NSWindow *)window;

- (BOOL)runCommandInSession:(PTYSession *)aSession
                      inCwd:(NSString *)oldCWD
              forObjectType:(iTermObjectType)objectType
           windowController:(PseudoTerminal *)windowController;


@end

NS_ASSUME_NONNULL_END
