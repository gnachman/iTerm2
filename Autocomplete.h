// Implements the Autocomplete UI. It grabs the word behind the cursor and opens a popup window with
// likely suffixes. Selecting one appends it, and you can search the list Quicksilver-style.

#import <Cocoa/Cocoa.h>
#import "PTYSession.h"
#import "LineBuffer.h"
#import "Popup.h"

@interface AutocompleteView : Popup

- (id)init;
- (void)dealloc;

- (void)onOpen;
- (void)refresh;
- (void)onClose;
- (void)rowSelected:(id)sender;
- (void)more;
- (void)less;
- (void)_populateMore:(id)sender;
- (void)_doPopulateMore;

@end

