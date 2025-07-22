//
//  PTYTextView+MouseHandler.h
//  iTerm2
//
//  Created by George Nachman on 7/21/25.
//

#import "iTerm2SharedARC-Swift.h"
#import "iTermSecureKeyboardEntryController.h"
#import "PTYMouseHandler.h"

@interface PTYTextView(MouseHandler)<iTermFocusFollowsMouseDelegate, iTermSecureInputRequesting, PTYMouseHandlerDelegate, iTermFocusFollowsMouseFocusReceiver>
@end

