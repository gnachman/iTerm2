#import <Cocoa/Cocoa.h>
#import "CPKColorWell.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (weak) IBOutlet CPKColorWell *colorWell;
@property (weak) IBOutlet CPKColorWell *continuousColorWell;

@property (weak) IBOutlet CPKColorWell *p3ColorWell;
@property (weak) IBOutlet CPKColorWell *p3ContinuousColorWell;

@property (weak) IBOutlet NSTextField *loremIpsum;

@end

