// Fixture: @selector expressions and reflective calls. Line numbers are part of the expectations.
#import "sel_base.h"
#define SEL_OF(x) @selector(x)
#define RELOAD_SEL @selector(reload)
#define kTitleKey @"title"
static NSString *const kNameKey = @"name";
// kSaveSel: a local constant, since a static SEL needs a constant initializer.

void Selectors(Base *b, NSString *dynamicName, SEL s) {
    SEL const kSaveSel = @selector(save:);
    SEL a = @selector(reload);
    SEL k = @selector(save:);
    SEL m = @selector(insert:at:);
    SEL n = SEL_OF(open:);
    SEL r = RELOAD_SEL;
    void (^blk)(void) = ^{ (void)@selector(inBlock); };
    NSSelectorFromString(NSStringFromSelector(@selector(reload)));
    NSSelectorFromString(@"reload");
    NSSelectorFromString(@"re" @"load");
    NSSelectorFromString(kNameKey);
    NSSelectorFromString(dynamicName);
    NSClassFromString(NSStringFromSelector(@selector(Gadget)));
    NSClassFromString(@"Gadget");
    NSClassFromString(kNameKey);
    NSClassFromString(dynamicName);
    [b performSelector:@selector(reload)];
    [b performSelector:NSSelectorFromString(@"save:")];
    [b performSelector:kSaveSel];
    [b performSelector:s withObject:b afterDelay:0];
    [b respondsToSelector:@selector(reload)];
    [b respondsToSelector:NSSelectorFromString(@"save:")];
    [b respondsToSelector:NSSelectorFromString(kNameKey)];
    [b respondsToSelector:s];
    [b valueForKey:NSStringFromSelector(@selector(title))];
    [b valueForKey:@"title"];
    [b valueForKey:kTitleKey];
    [b valueForKey:dynamicName];
    [b addObserver:b forKeyPath:NSStringFromSelector(@selector(count)) options:0 context:0];
    [b addObserver:b forKeyPath:@"title" options:0 context:0];
    [b addObserver:b forKeyPath:kNameKey options:0 context:0];
    [b addObserver:b forKeyPath:dynamicName options:0 context:0];
    [b setAction:@selector(reload)];
    [b setAction:NSSelectorFromString(@"open:")];
    [b setAction:kSaveSel];
    [b setAction:s];
    b.action = @selector(save:);
    [b setValue:b forKey:@"ti" @"tle"];
    method_exchangeImplementations(class_getInstanceMethod([Base class], @selector(reload)),
                                   class_getInstanceMethod(NSClassFromString(@"Gadget"), s));
    ((id (*)(id, SEL))objc_msgSend)(b, @selector(reload));
    sel_registerName("save:");
    (void)a; (void)k; (void)m; (void)n; (void)r; (void)blk;
}
