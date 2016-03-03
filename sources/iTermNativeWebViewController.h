//
//  iTermNativeWebViewController.h
//  iTerm2
//
//  Created by George Nachman on 3/2/16.
//
//
// The protocol:
//   App sends
//     OSC 1337;NativeView=<base64-encoded json> ST
//   iTerm2 creates the view and reports
//     OSC 1337;NativeViewHeightChange=<identifier>;<rows> ST
//   App sends
//     OSC 1337;NativeViewHeightAccepted=<identifier>;<rows> ST
//   iTerm2 changes the view's size
//   ...
//

#import "iTermNativeViewController.h"

@interface iTermNativeWebViewController : iTermNativeViewController

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

@end

