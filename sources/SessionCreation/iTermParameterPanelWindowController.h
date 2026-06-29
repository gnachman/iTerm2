//
//  iTermParameterPanelWindowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/3/18.
//

#import <Cocoa/Cocoa.h>

// Parameter Panel
// A bookmark may have metasyntactic variables like $$FOO$$ in the command.
// When opening such a bookmark, pop up a sheet and ask the user to fill in
// the value. These fields belong to that sheet.
@interface iTermParameterPanelWindowController : NSWindowController

@property (nonatomic, strong) IBOutlet NSTextField *parameterName;
@property (nonatomic, strong) IBOutlet NSTextField *parameterValue;
@property (nonatomic, strong) IBOutlet NSTextField *parameterPrompt;
@property (nonatomic, readonly) BOOL canceled;


@end
