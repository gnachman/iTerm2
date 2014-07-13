#import "iTermOpenQuicklyItem.h"
#import "iTermLogoGenerator.h"
#import "iTermOpenQuicklyTableCellView.h"

@implementation iTermOpenQuicklyItem

- (id)init {
    self = [super init];
    if (self) {
        _logoGenerator = [[iTermLogoGenerator alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_sessionId release];
    [_title release];
    [_detail release];
    [_view release];
    [_logoGenerator release];
    [super dealloc];
}

@end
