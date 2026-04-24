//
//  iTermTriState.h
//  iTerm2
//
//  Created by George Nachman on 7/31/25.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(int, iTermTriState) {
    iTermTriStateFalse,
    iTermTriStateTrue,
    iTermTriStateOther
};
iTermTriState iTermTriStateFromBool(BOOL b);
