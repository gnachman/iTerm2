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
    kiTermRestorableSessionGroupWindow,
    kiTermRestorableSessionGroupChannel
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
@property(nonatomic) iTermPercentage percentage;
@property(nonatomic) int screen;
@property(nonatomic, copy) NSString *windowTitle;
@property(nonatomic, copy) NSString *channelParentGuid;
// tab unique IDs of tabs that come before this one in the window.
@property(nonatomic, copy) NSArray *predecessors;
// Maps the GUID of each session in this group whose undo window ran out and
// that was archived to the path of its archive. `sessions` holds the ones that
// are still alive. Undo restores both.
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *archivePathsBySessionGUID;
// Set on entries restored after a restart, when tab unique IDs are no longer
// valid. They identify `tabUniqueId` and `predecessors` by tab GUID until the
// tabs are looked up.
@property(nonatomic, copy) NSString *tabGUID;
@property(nonatomic, copy) NSArray<NSString *> *predecessorTabGUIDs;

- (instancetype)initWithRestorableState:(NSDictionary *)restorableState;
- (NSDictionary *)restorableState;

@end
