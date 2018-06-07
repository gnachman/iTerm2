//
//  iTermSessionNameController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/16/18.
//

#import <Foundation/Foundation.h>

@class Profile;

@interface iTermSessionFormattingDescriptor : NSObject
@property (nonatomic) BOOL isTmuxGateway;
@property (nonatomic, copy) NSString *tmuxClientName;
@property (nonatomic) BOOL haveTmuxController;
@property (nonatomic, copy) NSString *tmuxWindowName;
@property (nonatomic, copy) NSString *jobName;
@end

@protocol iTermSessionNameControllerDelegate<NSObject>

- (void)sessionNameControllerNameWillChangeTo:(NSString *)newName;
- (void)sessionNameControllerPresentationNameDidChangeTo:(NSString *)newName;
- (void)sessionNameControllerDidChangeWindowTitle;
- (iTermSessionFormattingDescriptor *)sessionNameControllerFormattingDescriptor;
- (id (^)(NSString *))sessionNameControllerVariableSource;

@end

@interface iTermSessionNameController : NSObject

@property (nonatomic, weak) id<iTermSessionNameControllerDelegate> delegate;

// The first value assigned to sessionName.
@property (nonatomic, readonly) NSString *firstSessionName;

// Session name; can be changed via escape code or trigger.
@property (nonatomic, readonly) NSString *sessionName;

// Name with extra formatting, ready to be shown in a title bar.
@property (nonatomic, readonly) NSString *presentationName;

// Window title; can be changed by escape code or trigger. Is initialized to session name.
@property (nonatomic, readonly) NSString *windowTitle;

// Window title with extra formatting, ready to be shown in a title bar.
@property (nonatomic, readonly) NSString *presentationWindowTitle;

@property (nonatomic, readonly) NSString *terminalWindowName;
@property (nonatomic, readonly) NSString *terminalIconName;

+ (NSString *)titleFormatForProfile:(Profile *)profile;

- (instancetype)initWithProfileName:(NSString *)name
                        titleFormat:(NSString *)titleFormat NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)didInitializeSessionWithName:(NSString *)newName;
- (void)profileNameDidChangeTo:(NSString *)newName;
- (void)profileDidChangeToProfileWithName:(NSString *)newName;
- (void)terminalDidSetWindowTitle:(NSString *)newName;
- (void)terminalDidSetIconTitle:(NSString *)newName;
- (void)triggerDidChangeNameTo:(NSString *)newName;
- (void)setTmuxTitle:(NSString *)tmuxTitle;
- (void)didSynthesizeFrom:(iTermSessionNameController *)real;
- (void)restoreNameFromStateDictionary:(NSDictionary *)state
                     legacyProfileName:(NSString *)legacyProfileName
                     legacySessionName:(NSString *)legacyName
                     legacyWindowTitle:(NSString *)legacyWindowTitle;
- (NSDictionary *)stateDictionary;

- (void)pushWindowTitle;
- (void)popWindowTitle;
- (void)pushIconTitle;
- (void)popIconTitle;

@end

