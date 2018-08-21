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
  return [[NSBundle bundleForClass:self.class] imageForResource:@"new-tab"];
}

@end

@implementation iTermOpenQuicklyChangeProfileItem

- (NSImage *)icon {
    return [[NSBundle bundleForClass:self.class] imageForResource:@"ChangeProfile"];
}

@end

@implementation iTermOpenQuicklyColorPresetItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _logoGenerator = [[iTermLogoGenerator alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_logoGenerator release];
    [_presetName release];
    [super dealloc];
}

- (NSImage *)icon {
    return [_logoGenerator generatedImage];
}

@end

@implementation iTermOpenQuicklyArrangementItem

- (NSImage *)icon {
  return [[NSBundle bundleForClass:self.class] imageForResource:@"restore-arrangement"];
}

@end

@implementation iTermOpenQuicklyHelpItem

- (NSImage *)icon {
    return [[NSBundle bundleForClass:self.class] imageForResource:@"Info"];
}

@end

@implementation iTermOpenQuicklyScriptItem

- (NSImage *)icon {
    return [[NSBundle bundleForClass:self.class] imageForResource:@"ScriptIcon"];
}

@end

