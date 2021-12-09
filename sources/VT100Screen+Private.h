//
//  VT100Screen+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/9/21.
//

@interface VT100Screen() {
    id<VT100GridReading> primaryGrid_;
    id<VT100GridReading> altGrid_;  // may be nil
    id<VT100GridReading> currentGrid_;  // Weak reference. Points to either primaryGrid or altGrid.
    id<VT100GridReading> realCurrentGrid_;  // When a saved grid is swapped in, this is the live current grid.
}

@end
