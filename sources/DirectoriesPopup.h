//
//  DirectoriesPopup.h
//  iTerm
//
//  Created by George Nachman on 5/2/14.
//
//

#import "Popup.h"
#import "PopupEntry.h"

@class iTermDirectoryEntry;
@class VT100RemoteHost;

@interface DirectoriesPopupEntry : PopupEntry
@property(nonatomic, retain) iTermDirectoryEntry *entry;
@end

@interface DirectoriesPopupWindowController : Popup

- (void)loadDirectoriesForHost:(VT100RemoteHost *)host;

@end
