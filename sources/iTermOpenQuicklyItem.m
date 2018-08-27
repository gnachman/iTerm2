#import "iTermOpenQuicklyItem.h"
#import "iTermLogoGenerator.h"
#import "iTermOpenQuicklyTableCellView.h"
#import "NSImage+iTerm.h"

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
    return [NSImage it_imageNamed:@"new-tab" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyChangeProfileItem

- (NSImage *)icon {
    return [NSImage it_imageNamed:@"ChangeProfile" forClass:self.class];
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
  return [NSImage it_imageNamed:@"restore-arrangement" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyHelpItem

- (NSImage *)icon {
    return [NSImage it_imageNamed:@"Info" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyScriptItem

- (NSImage *)icon {
    return [NSImage it_imageNamed:@"ScriptIcon" forClass:self.class];
}

@end

