//
//  iTermRestorableSession.h
//  iTerm
//
//  Created by George Nachman on 5/30/14.
//
//

#import <Foundation/Foundation.h>

#import "ITAddressBookMgr.h"

typedef NS_ENUM(NSInteger, iTermRestorableSessionGroup) {
    kiTermRestorableSessionGroupSession,
    kiTermRestorableSessionGroupTab,
    kiTermRestorableSessionGroupWindow
};

@class PTYSession;

@interface iTermRestorableSession : NSObject

@property(nonatomic, strong) NSArray<PTYSession *> *sessions;
@property(nonatomic, copy) NSString *terminalGuid;
@property(nonatomic, assign) int tabUniqueId;
@property(nonatomic, strong) NSDictionary *arrangement;
@property(nonatomic) iTermRestorableSessionGroup group;
@property(nonatomic) iTermWindowType windowType;
@property(nonatomic) iTermWindowType savedWindowType;
@property(nonatomic) int screen;
@property(nonatomic, copy) NSString *windowTitle;

// tab unique IDs of tabs that come before this one in the window.
@property(nonatomic, copy) NSArray *predecessors;

- (instancetype)initWithRestorableState:(NSDictionary *)restorableState;
- (NSDictionary *)restorableState;

@end
