//
//  iTermMultiServerJobManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/25/19.
//

#import <Foundation/Foundation.h>
#import "PTYTask.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermMultiServerRestorationKeyType;
extern NSString *const iTermMultiServerRestorationKeyVersion;
extern NSString *const iTermMultiServerRestorationKeySocket;
extern NSString *const iTermMultiServerRestorationKeyChildPID;


//      ┌────────────────────────────┐     ┌────────────────────────────────┐
// ┌───>│ iTermMultiServerConnection │  ┌─>│ iTermFileDescriptorMultiClient │
// │    ├────────────────────────────┤  │  ├────────────────────────────────┤
// │ ┌──│╌+registry                  │  │  │ _readFD                        │
// │ │  │ _client ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│──┘  │ _writeFD                       │
// │ │  └────────────────────────────┘  ┌──│╌_children                      │
// │ │                           ^      │  └────────────────────────────────┘
// │ └─>┌─────────────────────┐  │      │
// │    │ NSMutableDictionary │  │      │   ┌─────────────────────────────────────┐
// │    ├─────────────────────│  │      └──>│ iTermFileDescriptorMultiClientChild │
// │    │ NSNumber -> Obj     │──┘        * ├─────────────────────────────────────┤
// │    └─────────────────────┘             │ - pid                               │
// │                                        │ - fd                                │
// │    ╔═════════════════╗                 │ - tty                               │
// │    ║ iTermJobManager ║<────────────┐   │ - terminationStatus                 │
// │    ╚═════════════════╝             │   └─────────────────────────────────────┘
// │            ▲ ▲ ▲                   │
// │            ║ ║ ║                   │   ┌─────────────┐
// │            ║ ║ ║                   │   │ PTYTask     │
// │            ║ ║ ║                   │   ├─────────────│
// │            ║ ║ ║                   └───│╌_jobManager │
// │            ║ ║ ║                       └─────────────┘
// │            ║ ║ ╚════════════════════════════════════════╗
// │            ║ ╚════════════╗                             ║
// │            ║              ║                             ║
// │            ║              ║                             ║
// │            ║ ┌───────────────────────────┐  ┌─────────────────────────────┐
// │            ║ │ iTermMonoServerJobManager │  │ iTermLegacyServerJobManager │
// │            ║ └───────────────────────────┘  └─────────────────────────────┘
// │            ║
// │   ┌────────────────────────────┐       ┌─────────────────────────────────────┐
// │   │ iTermMultiServerJobManager │   ┌──>│ iTermFileDescriptorMultiClientChild │
// │   ├────────────────────────────┤   │   ├─────────────────────────────────────┤
// └───│╌_conn                      │   │   │ - pid                               │
//     │ _child╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│───┘   │ - fd                                │
//     └────────────────────────────┘       │ - tty                               │
//                                          │ - terminationStatus                 │
//                                          └─────────────────────────────────────┘
//

@interface iTermMultiServerJobManager : NSObject<iTermJobManager>

+ (BOOL)getGeneralConnection:(iTermGeneralServerConnection *)generalConnection
   fromRestorationIdentifier:(NSDictionary *)dict;

// In-process freeze/thaw support. Detaches the running child from this job
// manager and returns it to its connection's unattached list so it can be
// re-adopted on thaw, WITHOUT closing the child's file descriptor and WITHOUT
// tearing down the shared connection. Returns the parked child's pid, or -1 if
// there was nothing to park (e.g., no live child or non-multiserver child).
- (pid_t)parkChildForReattachment;
@end

NS_ASSUME_NONNULL_END
