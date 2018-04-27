//
//  iTermScriptTemplatePickerWindowController.h
//  iTerm2
//
//  Created by George Nachman on 4/26/18.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, iTermScriptEnvironment) {
    iTermScriptEnvironmentNone,
    iTermScriptEnvironmentBasic,
    iTermScriptEnvironmentPrivateEnvironment
};

typedef NS_ENUM(NSInteger, iTermScriptTemplate) {
    iTermScriptTemplateNone,
    iTermScriptTemplateSimple,
    iTermScriptTemplateDaemon
};

@interface iTermScriptTemplatePickerWindowController : NSWindowController

@property (nonatomic, readonly) iTermScriptEnvironment selectedEnvironment;
@property (nonatomic, readonly) iTermScriptTemplate selectedTemplate;

@end
