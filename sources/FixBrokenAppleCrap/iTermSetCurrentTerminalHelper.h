//
//  iTermSetCurrentTerminalHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/18.
//

#import <Foundation/Foundation.h>

@class PseudoTerminal;

@protocol iTermSetCurrentTerminalHelperDelegate<NSObject>
- (void)reallySetCurrentTerminal:(PseudoTerminal *)thePseudoTerminal;
@end

// This is a hack to work around an AppKit bug. See issue 6748
@interface iTermSetCurrentTerminalHelper : NSObject
@property (nonatomic, weak) id<iTermSetCurrentTerminalHelperDelegate> delegate;

- (void)setCurrentTerminal:(PseudoTerminal *)thePseudoTerminal;

@end
