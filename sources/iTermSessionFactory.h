//
//  iTermSessionFactory.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/3/18.
//

#import <Foundation/Foundation.h>

#import "ITAddressBookMgr.h"
#import "iTermFileDescriptorClient.h"
#import "PTYTask.h"

NS_ASSUME_NONNULL_BEGIN

@class PTYSession;
@class Profile;
@class PseudoTerminal;

@interface iTermSessionAttachOrLaunchRequest: NSObject
@property (nonatomic, strong) PTYSession *session;
@property (nonatomic) BOOL canPrompt;
@property (nonatomic) iTermObjectType objectType;
@property (nonatomic) BOOL hasServerConnection;
@property (nonatomic) iTermGeneralServerConnection xx_serverConnection;
@property (nonatomic, nullable, copy) NSString *urlString;
@property (nonatomic) BOOL allowURLSubs;
@property (nonatomic, nullable, copy) NSDictionary *environment;
@property (nonatomic, nullable, copy) NSString *customShell;
@property (nonatomic, nullable, copy) NSString *oldCWD;
@property (nonatomic) BOOL forceUseOldCWD;  // Change custom directory setting to make it use the passed-in oLDCWD
@property (nonatomic, nullable, copy) NSString *command;   // Overrides profile's command if nonnil
@property (nonatomic) BOOL isUTF8;
@property (nonatomic, nullable, copy) NSDictionary *substitutions;
@property (nonatomic, strong) PseudoTerminal *windowController;
@property (nonatomic, nullable, copy) void (^ready)(BOOL ok);
@property (nonatomic, nullable, copy) void (^completion)(PTYSession * _Nullable session, BOOL ok);  // If nonnil, attachorLaunch may be async
// Name of the arrangement from which this request originated.
@property (nullable, nonatomic, copy) NSString *arrangementName;
@property (nonatomic, strong) id<iTermPartialAttachment> partialAttachment;
@property (nonatomic) BOOL fromArrangement;

+ (instancetype)launchRequestWithSession:(PTYSession *)aSession
                               canPrompt:(BOOL)canPrompt
                              objectType:(iTermObjectType)objectType
                     hasServerConnection:(BOOL)hasServerConnection
                        serverConnection:(iTermGeneralServerConnection)serverConnection
                               urlString:(nullable NSString *)urlString
                            allowURLSubs:(BOOL)allowURLSubs
                             environment:(nullable NSDictionary *)environment
                             customShell:(nullable NSString *)customShell
                                  oldCWD:(nullable NSString *)oldCWD
                          forceUseOldCWD:(BOOL)forceUseOldCWD
                                 command:(nullable NSString *)command
                                  isUTF8:(nullable NSNumber *)isUTF8Number  // Overrides profile's iSUTF8 if nonnil
                           substitutions:(nullable NSDictionary *)substitutions
                        windowController:(PseudoTerminal * _Nonnull)windowController
                                   ready:(void (^ _Nullable)(BOOL ok))ready
                              completion:(void (^ _Nullable)(PTYSession * _Nullable, BOOL))completion;

@end

@interface iTermSessionFactory : NSObject

@property (nonatomic) BOOL promptingDisabled;

- (PTYSession *)newSessionWithProfile:(Profile *)profile
                               parent:(nullable PTYSession *)parent;

- (void)attachOrLaunchWithRequest:(iTermSessionAttachOrLaunchRequest *)request;

@end

NS_ASSUME_NONNULL_END
