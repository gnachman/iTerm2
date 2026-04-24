#import "iTermOpenQuicklyItem.h"
#import "SFSymbolEnum/SFSymbolEnum.h"
#import "iTermLogoGenerator.h"
#import "iTermOpenQuicklyTableCellView.h"
#import "NSImage+iTerm.h"

@implementation iTermOpenQuicklyItem
@end

@implementation iTermOpenQuicklySessionItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _logoGenerator = [[iTermLogoGenerator alloc] init];
    }
    return self;
}

- (NSImage *)icon {
    return [_logoGenerator generatedImage];
}

@end

@implementation iTermOpenQuicklyWindowItem

- (NSImage *)icon {
    return [NSImage it_imageNamed:@"Window" forClass:self.class];
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

@implementation iTermOpenQuicklyActionItem : iTermOpenQuicklyItem

- (NSImage *)icon {
    return [NSImage it_imageNamed:@"OpenQuicklyActionIcon" forClass:self.class];
}

@end

@implementation iTermOpenQuicklySnippetItem : iTermOpenQuicklyItem

- (NSImage *)icon {
    return [NSImage it_imageNamed:@"OpenQuicklySnippetIcon" forClass:self.class];
}

// This can be the sender to -sendSnippet:
- (id)representedObject {
    return self.snippet;
}

@end

@implementation iTermOpenQuicklyInvocationItem

- (NSImage *)icon {
    return [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolFunction) accessibilityDescription:nil];
}

@end

@implementation iTermOpenQuicklyNamedMarkItem

- (NSImage *)icon {
    return [NSImage it_imageNamed:@"OpenQuicklyNamedMark" forClass:self.class];
}

@end

@implementation iTermOpenQuicklyMenuItem

- (NSImage *)icon {
    NSImage *image = [NSImage it_imageNamed:@"OpenQuicklyMenuItem" forClass:self.class];
    image.template = YES;
    return image;
}

- (BOOL)valid {
    return self.menuItem.isEnabled && !self.menuItem.isHidden;
}

@end

@implementation iTermOpenQuicklyBookmarkItem

- (NSImage *)icon {
    if (@available(macOS 11, *)) {
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:32 weight:NSFontWeightRegular];
        NSImage *image = [NSImage imageWithSystemSymbolName:SFSymbolGetString(SFSymbolBookmark) accessibilityDescription:@"globe"];
        image = [image imageWithSymbolConfiguration:config];
        image.size = NSMakeSize(32, 32);
        return image;
    }
    return nil;
}

@end

@implementation iTermOpenQuicklyURLItem

- (NSImage *)icon {
    if (@available(macOS 11, *)) {
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:32 weight:NSFontWeightRegular];
        NSImage *image = [NSImage imageWithSystemSymbolName:SFSymbolGetString(SFSymbolGlobe) accessibilityDescription:@"globe"];
        image = [image imageWithSymbolConfiguration:config];
        image.size = NSMakeSize(32, 32);
        return image;
    }
    return nil;
}

@end

