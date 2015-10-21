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
@class VT100RemoteHost;

@interface DirectoriesPopupEntry : PopupEntry
@property(nonatomic, retain) iTermRecentDirectoryMO *entry;
@end

@interface DirectoriesPopupWindowController : iTermPopupWindowController

- (void)loadDirectoriesForHost:(VT100RemoteHost *)host;

@end
