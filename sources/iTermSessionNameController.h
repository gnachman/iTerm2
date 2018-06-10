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
- (NSString *)sessionNameControllerInvocation;

@end

@interface iTermSessionNameController : NSObject

@property (nonatomic, weak) id<iTermSessionNameControllerDelegate> delegate;
// Window title with extra formatting, ready to be shown in a title bar.
@property (nonatomic, readonly) NSString *presentationWindowTitle;

// Name with extra formatting, ready to be shown in a title bar.
@property (nonatomic, readonly) NSString *presentationSessionTitle;

- (void)restoreNameFromStateDictionary:(NSDictionary *)state;
- (NSDictionary *)stateDictionary;

- (void)pushWindowTitle;
- (NSString *)popWindowTitle;
- (void)pushIconTitle;
- (NSString *)popIconTitle;

- (void)variablesDidChange:(NSSet<NSString *> *)names;

// Forces a synchronous eval followed by an async.
- (void)setNeedsUpdate;

- (void)updateIfNeeded;

@end

