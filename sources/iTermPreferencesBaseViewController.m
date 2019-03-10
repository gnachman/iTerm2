//
//  iTermPreferencesBaseViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "iTermPreferences.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"

#import <ColorPicker/ColorPicker.h>

@interface iTermPreferencesInnerTabContainerView : NSView
@end

@implementation iTermPreferencesInnerTabContainerView
@end

static NSString *const kPreferenceDidChangeFromOtherPanel = @"kPreferenceDidChangeFromOtherPanel";

// key for userInfo dictionary of kPreferenceDidChangeFromOtherPanel notification having
// key of changed preference.
NSString *const kPreferenceDidChangeFromOtherPanelKeyUserInfoKey = @"key";

@interface iTermPreferencesBaseViewController()
// If set to YES, then controls won't be updated with values from backing store when it changes.
@property(nonatomic, assign) BOOL disableUpdates;
@end

@implementation iTermPreferencesBaseViewController {
    // Maps NSControl* -> PreferenceInfo*.
    NSMapTable *_keyMap;
    // Set of all defined keys (KEY_XXX).
    NSMutableSet *_keys;

    NSRect _desiredFrame;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _keyMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory
                                            valueOptions:NSPointerFunctionsStrongMemory
                                                capacity:16];
        _keys = [[NSMutableSet alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferenceDidChangeFromOtherPanel:)
                                                     name:kPreferenceDidChangeFromOtherPanel
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferencePanelWillClose:)
                                                     name:kPreferencePanelWillCloseNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (PreferenceInfo *)infoForKey:(NSString *)key {
    for (NSControl *control in _keyMap) {
        PreferenceInfo *info = [self infoForControl:control];
        if ([info.key isEqualToString:key]) {
            return info;
        }
    }
    return nil;
}

#pragma mark - Methods to override

- (void)setObjectsFromDictionary:(NSDictionary *)dictionary {
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [self setObject:obj forKey:key];
    }];
}

- (BOOL)boolForKey:(NSString *)key {
    return [iTermPreferences boolForKey:key];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [iTermPreferences setBool:value forKey:key];
}

- (int)intForKey:(NSString *)key {
    return [iTermPreferences intForKey:key];
}

- (void)setInt:(int)value forKey:(NSString *)key {
    [iTermPreferences setInt:value forKey:key];
}

- (NSInteger)integerForKey:(NSString *)key {
    return [iTermPreferences integerForKey:key];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [iTermPreferences setInteger:value forKey:key];
}

- (NSUInteger)unsignedIntegerForKey:(NSString *)key {
    return [iTermPreferences unsignedIntegerForKey:key];
}

- (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key {
    [iTermPreferences setUnsignedInteger:value forKey:key];
}

- (double)floatForKey:(NSString *)key {
    return [iTermPreferences floatForKey:key];
}

- (void)setFloat:(double)value forKey:(NSString *)key {
    [iTermPreferences setFloat:value forKey:key];
}

- (double)doubleForKey:(NSString *)key {
    return [iTermPreferences doubleForKey:key];
}

- (void)setDouble:(double)value forKey:(NSString *)key {
    [iTermPreferences setDouble:value forKey:key];
}

- (NSString *)stringForKey:(NSString *)key {
    return [iTermPreferences stringForKey:key];
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    [iTermPreferences setString:value forKey:key];
}

- (NSObject *)objectForKey:(NSString *)key {
    return [iTermPreferences objectForKey:key];
}

- (void)setObject:(NSObject *)object forKey:(NSString *)key {
    [iTermPreferences setObject:object forKey:key];
}

- (BOOL)keyHasDefaultValue:(NSString *)key {
    return [iTermPreferences keyHasDefaultValue:key];
}

- (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type {
    return [iTermPreferences defaultValueForKey:key isCompatibleWithType:type];
}

- (BOOL)shouldUpdateOtherPanels {
    return YES;
}

#pragma mark - APIs

- (IBAction)settingChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:sender];
    assert(info);

    if (info.willChange) {
        info.willChange();
    }

    if (info.customSettingChangedHandler) {
        info.customSettingChangedHandler(sender);
    } else {
        switch (info.type) {
            case kPreferenceInfoTypeCheckbox:
                [self setBool:([sender state] == NSOnState) forKey:info.key];
                break;

            case kPreferenceInfoTypeInvertedCheckbox:
                [self setBool:([sender state] == NSOffState) forKey:info.key];
                break;

            case kPreferenceInfoTypeIntegerTextField:
                [self applyIntegerConstraints:info];
                const int intValue = [sender separatorTolerantIntValue];
                if (!info.deferUpdate) {
                    [self setInt:intValue forKey:info.key];
                }
                break;

            case kPreferenceInfoTypeDoubleTextField: {
                NSScanner *scanner = [NSScanner localizedScannerWithString:[sender stringValue]];
                double value;
                if ([scanner scanDouble:&value]) {
                    // A double value may take a legal but non-canonical form during editing. For
                    // example, "1." is a valid way of specifying 1.0. But we don't want to replace
                    // the control's value with "1", or there's no way of entering "1.2", for
                    // example. We turn on disableUpdates so -setDouble:forKey: doesn't have the
                    // side-effect of updating the control with its canonical value.
                    BOOL savedValue = self.disableUpdates;
                    self.disableUpdates = YES;
                    [self setDouble:value forKey:info.key];
                    self.disableUpdates = savedValue;
                }
                break;
            }

            case kPreferenceInfoTypeUnsignedIntegerTextField:
                [self applyUnsignedIntegerConstraints:info];
                [self setUnsignedInteger:[sender separatorTolerantUnsignedIntegerValue] forKey:info.key];
                break;

            case kPreferenceInfoTypeStringTextField:
                [self setString:[sender stringValue] forKey:info.key];
                break;

            case kPreferenceInfoTypeTokenField:
                [self setObject:[sender objectValue] forKey:info.key];
                break;

            case kPreferenceInfoTypeMatrix:
            case kPreferenceInfoTypeRadioButton:
                assert(false);  // Must use a custom setting changed handler

            case kPreferenceInfoTypePopup:
                [self setInt:[sender selectedTag] forKey:info.key];
                break;

            case kPreferenceInfoTypeUnsignedIntegerPopup:
                assert([sender selectedTag]>=0);
                [self setUnsignedInteger:[sender selectedTag] forKey:info.key];
                break;

            case kPreferenceInfoTypeSlider:
                [self setFloat:[sender doubleValue] forKey:info.key];
                break;

            case kPreferenceInfoTypeColorWell:
                [self setObject:[[sender color] dictionaryValue] forKey:info.key];
                break;

            default:
                assert(false);
        }
        if (info.onChange) {
            info.onChange();
        }
    }
    if (info.observer) {
        info.observer();
    }
    if ([self shouldUpdateOtherPanels]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPreferenceDidChangeFromOtherPanel
                                                            object:self
                                                          userInfo:@{ kPreferenceDidChangeFromOtherPanelKeyUserInfoKey: info.key }];
    }

}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type {
    return [self defineControl:control
                           key:key
                          type:type
                settingChanged:NULL
                        update:NULL];
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^)(id))settingChanged
                           update:(BOOL (^)(void))update {
    assert(![_keyMap objectForKey:key]);
    assert(key);
    assert(control);
    assert([self keyHasDefaultValue:key]);
    if (!settingChanged || !update) {
        assert([self defaultValueForKey:key isCompatibleWithType:type]);
        assert(type != kPreferenceInfoTypeMatrix);  // Matrix type requires both.
        assert(type != kPreferenceInfoTypeRadioButton);  // This is just a modernized matrix
    }
    PreferenceInfo *info = [PreferenceInfo infoForPreferenceWithKey:key
                                                               type:type
                                                            control:control];
    info.customSettingChangedHandler = settingChanged;
    info.onUpdate = update;
    [_keyMap setObject:info forKey:control];
    [_keys addObject:key];
    [self updateValueForInfo:info];

    return info;
}

- (void)updateValueForInfo:(PreferenceInfo *)info {
    if (_disableUpdates) {
        return;
    }
    if (info.onUpdate) {
        if (info.onUpdate()) {
            return;
        }
    }
    switch (info.type) {
        case kPreferenceInfoTypeCheckbox: {
            assert([info.control isKindOfClass:[NSButton class]]);
            NSButton *button = (NSButton *)info.control;
            button.state = [self boolForKey:info.key] ? NSOnState : NSOffState;
            break;
        }

        case kPreferenceInfoTypeInvertedCheckbox: {
            assert([info.control isKindOfClass:[NSButton class]]);
            NSButton *button = (NSButton *)info.control;
            button.state = [self boolForKey:info.key] ? NSOffState : NSOnState;
            break;
        }

        case kPreferenceInfoTypeIntegerTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.intValue = [self intForKey:info.key];
            break;
        }

        case kPreferenceInfoTypeUnsignedIntegerTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.stringValue = [NSString stringWithFormat:@"%lu", [self unsignedIntegerForKey:info.key]];
        }

        case kPreferenceInfoTypeDoubleTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.doubleValue = [self doubleForKey:info.key];
            break;
        }

        case kPreferenceInfoTypeStringTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.stringValue = [self stringForKey:info.key] ?: @"";
            break;
        }

        case kPreferenceInfoTypeTokenField: {
            assert([info.control isKindOfClass:[NSTokenField class]]);
            NSTokenField *field = (NSTokenField *)info.control;
            NSObject *object = [self objectForKey:info.key];;
            assert(!object || [object conformsToProtocol:@protocol(NSCopying)]);
            field.objectValue = (id<NSCopying>)object;
            break;
        }

        case kPreferenceInfoTypePopup: {
            assert([info.control isKindOfClass:[NSPopUpButton class]]);
            NSPopUpButton *popup = (NSPopUpButton *)info.control;
            [popup selectItemWithTag:[self intForKey:info.key]];
            break;
        }

        case kPreferenceInfoTypeUnsignedIntegerPopup: {
            assert([info.control isKindOfClass:[NSPopUpButton class]]);
            NSPopUpButton *popup = (NSPopUpButton *)info.control;
            const NSUInteger value = [self unsignedIntegerForKey:info.key];
            assert(value <= NSIntegerMax);
            [popup selectItemWithTag:value];
            break;
        }

        case kPreferenceInfoTypeSlider: {
            assert([info.control isKindOfClass:[NSSlider class]]);
            NSSlider *slider = (NSSlider *)info.control;
            slider.doubleValue = [self floatForKey:info.key];
            break;
        }

        case kPreferenceInfoTypeMatrix:
        case kPreferenceInfoTypeRadioButton:
            assert(false);  // Must use onChange() only.

        case kPreferenceInfoTypeColorWell: {
            assert([info.control isKindOfClass:[CPKColorWell class]]);
            CPKColorWell *colorWell = (CPKColorWell *)info.control;
            NSDictionary *dict = (NSDictionary *)[self objectForKey:info.key];
            if (dict) {
                assert([dict isKindOfClass:[NSDictionary class]]);
                [colorWell setColor:[dict colorValue]];
            }
            break;
        }

        default:
            assert(false);
    }
    if (info.observer) {
        info.observer();
    }
}

- (void)updateEnabledState {
    for (NSControl *control in _keyMap) {
        PreferenceInfo *info = [self infoForControl:control];
        [self updateEnabledStateForInfo:info];
    }
}

- (void)updateEnabledStateForInfo:(PreferenceInfo *)info {
    if (info.shouldBeEnabled) {
        [info.control setEnabled:info.shouldBeEnabled()];
    }
}

- (PreferenceInfo *)infoForControl:(NSControl *)control {
    PreferenceInfo *info = [_keyMap objectForKey:control];
    assert(info);
    return info;
}

- (void)postRefreshNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (NSArray *)keysForBulkCopy {
    return [_keys allObjects];
}

- (void)windowWillClose {
    // Documented as doing nothing.
}

#pragma mark - Private

- (void)saveDeferredUpdates {
    [_keys enumerateObjectsUsingBlock:^(id  _Nonnull key, BOOL * _Nonnull stop) {
        PreferenceInfo *info = [self infoForKey:key];
        if (info.deferUpdate) {
            switch (info.type) {
                case kPreferenceInfoTypeIntegerTextField:
                    [self setInt:[[NSTextField castFrom:info.control] separatorTolerantIntValue] forKey:key];
                    break;

                case kPreferenceInfoTypeCheckbox:
                case kPreferenceInfoTypeInvertedCheckbox:
                case kPreferenceInfoTypeUnsignedIntegerTextField:
                case kPreferenceInfoTypeDoubleTextField:
                case kPreferenceInfoTypeStringTextField:
                case kPreferenceInfoTypePopup:
                case kPreferenceInfoTypeUnsignedIntegerPopup:
                case kPreferenceInfoTypeSlider:
                case kPreferenceInfoTypeTokenField:
                case kPreferenceInfoTypeMatrix:
                case kPreferenceInfoTypeColorWell:
                case kPreferenceInfoTypeRadioButton:
                    break;
            }
        }
    }];
}
#pragma mark - Constraints

// Pick out the digits from s and clamp it to a range.
- (int)intForString:(NSString *)s inRange:(NSRange)range
{
    NSString *i = [s stringWithOnlyDigits];

    int val = 0;
    if ([i length]) {
        val = [i intValue];
    }
    val = MAX(val, range.location);
    val = MIN(val, range.location + range.length - 1);
    return val;
}

- (NSUInteger)unsignedIntegerForString:(NSString *)s inRange:(NSRange)range {
    NSString *i = [s stringWithOnlyDigits];

    NSUInteger val = 0;
    if ([i length]) {
        val = [i iterm_unsignedIntegerValue];
    }
    val = MAX(val, range.location);
    val = MIN(val, range.location + range.length - 1);
    return val;
}

- (void)applyIntegerConstraints:(PreferenceInfo *)info {
    // NSNumberFormatter seems to have lost its mind on Lion. See a description of the problem here:
    // http://stackoverflow.com/questions/7976951/nsnumberformatter-erasing-value-when-it-violates-constraints
    assert([info.control isKindOfClass:[NSTextField class]]);
    NSTextField *textField = (NSTextField *)info.control;
    int iv = [self intForString:[textField stringValue] inRange:info.range];
    if (iv != [textField separatorTolerantIntValue]) {
        // If the int values don't match up or there are terminal non-number
        // chars, then update the value.
        [textField setIntValue:iv];
    }
}

- (void)applyUnsignedIntegerConstraints:(PreferenceInfo *)info {
    assert([info.control isKindOfClass:[NSTextField class]]);
    NSTextField *textField = (NSTextField *)info.control;
    NSUInteger iv = [self unsignedIntegerForString:[textField stringValue] inRange:info.range];
    if (iv != [textField separatorTolerantUnsignedIntegerValue]) {
        [textField setStringValue:[NSString stringWithFormat:@"%lu", iv]];
    }
}

#pragma mark - NSControl Delegate Informal Protocol

// This is a notification signature but it gets called because we're the delegate of text fields.
- (void)controlTextDidChange:(NSNotification *)aNotification {
    id control = [aNotification object];
    PreferenceInfo *info = [_keyMap objectForKey:control];
    if (info) {
        [self settingChanged:control];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification {
    id control = [aNotification object];
    PreferenceInfo *info = [_keyMap objectForKey:control];
    if (info.controlTextDidEndEditing) {
        info.controlTextDidEndEditing(aNotification);
    } else {
        switch (info.type) {
            case kPreferenceInfoTypeCheckbox:
            case kPreferenceInfoTypeColorWell:
            case kPreferenceInfoTypeInvertedCheckbox:
            case kPreferenceInfoTypeMatrix:
            case kPreferenceInfoTypeRadioButton:
            case kPreferenceInfoTypePopup:
            case kPreferenceInfoTypeSlider:
            case kPreferenceInfoTypeStringTextField:
            case kPreferenceInfoTypeTokenField:
            case kPreferenceInfoTypeUnsignedIntegerPopup:
            case kPreferenceInfoTypeUnsignedIntegerTextField:
                break;

            case kPreferenceInfoTypeIntegerTextField:
                if (info.deferUpdate) {
                    const int intValue = [[NSTextField castFrom:info.control] separatorTolerantIntValue];
                    [self setInt:intValue forKey:info.key];
                }
                break;

            case kPreferenceInfoTypeDoubleTextField:
                // Replace the control with its canonical value. Only floating point text fields can
                // temporarily take illegal values, which are tolerated until editing ends.
                // See the comments in -settingChanged: for more details on why doubles are special.
                [control setDoubleValue:[self doubleForKey:info.key]];
                break;
        }
    }
}

#pragma mark - Notifications

- (void)preferenceDidChangeFromOtherPanel:(NSNotification *)notification {
    NSString *key = notification.userInfo[kPreferenceDidChangeFromOtherPanelKeyUserInfoKey];
    if (![_keys containsObject:key]) {
        return;
    }
    PreferenceInfo *info = [self infoForKey:key];
    assert(info);
    if (!info.deferUpdate) {
        [self updateValueForInfo:info];
    }
}

- (void)preferencePanelWillClose:(NSNotification *)notification {
    if (_preferencePanel == notification.object) {
        [self saveDeferredUpdates];
        // Give subclasses a chance to do something first.
        [self windowWillClose];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_keyMap removeAllObjects];
        });
    }
}

- (NSTabView *)tabView {
    return nil;
}

- (CGFloat)minimumWidth {
    return 0;
}

- (void)resizeWindowForCurrentTabAnimated:(BOOL)animated {
    if (!self.tabView) {
        return;
    }
    [self resizeWindowForTabViewItem:self.tabView.selectedTabViewItem
                            animated:animated];
}

- (void)resizeWindowForTabViewItem:(NSTabViewItem *)tabViewItem
                          animated:(BOOL)animated {
    NSView *theView = tabViewItem.view.subviews.firstObject;
    [self resizeWindowForView:theView tabView:self.tabView animated:animated];
}

- (NSRect)windowFrameForTabViewSize:(NSSize)tabViewSize tabView:(NSTabView *)tabView {
    NSWindow *window = self.view.window;
    NSView *contentView = window.contentView;
    const CGFloat left = NSMinX([tabView convertRect:tabView.bounds toView:contentView]);
    const CGFloat right = NSWidth(contentView.frame) - NSMaxX([tabView convertRect:tabView.bounds
                                                                             toView:contentView]);
    const CGFloat below = NSMinY([tabView convertRect:tabView.bounds toView:contentView]);
    const CGFloat above = NSHeight(contentView.frame) - NSMaxY([tabView convertRect:tabView.bounds
                                                                              toView:contentView]);
    const NSRect contentViewFrame = NSMakeRect(0,
                                               0,
                                               left + tabViewSize.width + right,
                                               below + tabViewSize.height + above);
    const NSSize windowSize = [window frameRectForContentRect:contentViewFrame].size;
    const NSPoint windowTopLeft = NSMakePoint(NSMinX(window.frame),
                                              NSMaxY(window.frame));
    return NSMakeRect(windowTopLeft.x,
                      windowTopLeft.y - windowSize.height,
                      windowSize.width,
                      windowSize.height);
}

- (void)resizeWindowForView:(NSView *)theView tabView:(NSTabView *)tabView animated:(BOOL)animated {
    const CGFloat kTabViewMinWidth = self.minimumWidth;
    const CGFloat inset = NSWidth(tabView.bounds) - NSWidth(theView.superview.bounds);
    const CGFloat bottomMargin = 36;
    CGSize tabViewSize = NSMakeSize(MAX(kTabViewMinWidth, theView.bounds.size.width) + inset,
                                    theView.bounds.size.height + bottomMargin);
    NSRect frame = [self windowFrameForTabViewSize:tabViewSize tabView:tabView];
    if (NSEqualRects(_desiredFrame, frame)) {
        return;
    }
    NSWindow *window = self.view.window;
    if (!animated) {
        _desiredFrame = NSZeroRect;
        [window setFrame:frame display:YES];
        return;
    }

    // Animated
    _desiredFrame = frame;
    NSTimeInterval duration = [window animationResizeTime:frame];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        [window.animator setFrame:frame display:YES];
    } completionHandler:^{
        self->_desiredFrame = NSZeroRect;
        NSRect rect = frame;
        [window setFrame:rect display:YES];
    }];
}

#pragma mark - NSTabViewDelegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    assert(self.tabView);
    [self resizeWindowForTabViewItem:tabViewItem animated:YES];
}

@end
