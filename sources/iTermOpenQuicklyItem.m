#import "iTermOpenQuicklyItem.h"
#import "iTermLogoGenerator.h"
#import "iTermOpenQuicklyTableCellView.h"

@implementation iTermOpenQuicklyItem

- (void)dealloc {
    [_identifier release];
    [_title release];
    [_detail release];
    [_view release];
    [super dealloc];
}

@end

@implementation iTermOpenQuicklySessionItem

- (instancetype)init {
  self = [super init];
  if (self) {
    _logoGenerator = [[iTermLogoGenerator alloc] init];
  }
  return self;
}

- (void)dealloc {
  [_logoGenerator release];
  [super dealloc];
}

- (NSImage *)icon {
  return [_logoGenerator generatedImage];
}

@end

@implementation iTermOpenQuicklyProfileItem

- (NSImage *)icon {
  return [NSImage imageNamed:@"new-tab"];
}

@end

@implementation iTermOpenQuicklyChangeProfileItem

- (NSImage *)icon {
    return [NSImage imageNamed:@"ChangeProfile"];
}

@end

@implementation iTermOpenQuicklyArrangementItem

- (NSImage *)icon {
  return [NSImage imageNamed:@"restore-arrangement"];
}

@end

@implementation iTermOpenQuicklyHelpItem

- (NSImage *)icon {
    return [NSImage imageNamed:@"Info"];
}

@end