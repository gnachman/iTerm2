#import <Cocoa/Cocoa.h>
#import "CPKColorWell.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (weak) IBOutlet CPKColorWell *colorWell;
@property (weak) IBOutlet NSTextField *loremIpsum;

@end

