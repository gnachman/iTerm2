
#import <Cocoa/Cocoa.h>

// Adds a detailTextField to a NSTableCellView, which is bound to a field in
// iTermOpenQuicklyWindowController.xib
@interface iTermOpenQuicklyTableCellView : NSTableCellView

@property (nonatomic, retain) IBOutlet NSTextField *detailTextField;

@end
