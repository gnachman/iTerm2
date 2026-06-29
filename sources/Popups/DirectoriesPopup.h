//
//  DirectoriesPopup.h
//  iTerm
//
//  Created by George Nachman on 5/2/14.
//
//

#import "iTermPopupWindowController.h"
#import "PopupEntry.h"

@class iTermRecentDirectoryMO;
@protocol VT100RemoteHostReading;

@interface DirectoriesPopupEntry : PopupEntry
@property(nonatomic, retain) iTermRecentDirectoryMO *entry;
@end

@interface DirectoriesPopupWindowController : iTermPopupWindowController

- (void)loadDirectoriesForHost:(id<VT100RemoteHostReading>)host;

@end
