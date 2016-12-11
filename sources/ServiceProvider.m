//
//  ServiceProvider.m
//  iTerm2
//
//  Created by liupeng on 08/12/2016.
//
//

#import "ServiceProvider.h"
#import "iTermController.h"

@implementation ServiceProvider
- (void)openTab:(NSPasteboard*)pasteboard : (NSString*) error
{
    NSArray * filePathArray = [self parserPasteboard:pasteboard];
    if(!filePathArray || [filePathArray count] <=0 )
    {
        return;
    }
     //just test first file path and launch iTerm 2 in new tab at current window
    [[iTermController sharedInstance] launchBookmark:nil inTerminal:nil withURL:nil hotkeyWindowType:iTermHotkeyWindowTypeNone makeKey:YES canActivate:YES command:nil block:^PTYSession *(Profile *profile, PseudoTerminal *term) {
        profile = [profile dictionaryBySettingObject:@"Yes" forKey:KEY_CUSTOM_DIRECTORY];
        profile = [profile dictionaryBySettingObject:filePathArray[0] forKey:KEY_WORKING_DIRECTORY];
        return [term createTabWithProfile:profile withCommand:nil];
    }];
    
}
- (void)openWindow:(NSPasteboard*)pasteboard : (NSString*) error
{
    NSArray * filePathArray = [self parserPasteboard:pasteboard];
    if(!filePathArray || [filePathArray count] <=0 )
    {
        return;
    }
     //just test first file path and launch iTerm 2 in new window
    [[iTermController sharedInstance] launchBookmark:nil inTerminal:nil withURL:nil hotkeyWindowType:iTermHotkeyWindowTypeNone makeKey:YES canActivate:YES command:nil block:^PTYSession *(Profile *profile, PseudoTerminal *term) {
        profile = [profile dictionaryBySettingObject:@"Yes" forKey:KEY_CUSTOM_DIRECTORY];
        profile = [profile dictionaryBySettingObject:filePathArray[0] forKey:KEY_WORKING_DIRECTORY];
        return [term createTabWithProfile:profile withCommand:nil];
    }];

}
-(NSArray *)parserPasteboard:(NSPasteboard*)pasteboard
{
    NSString* PBoardString = [[pasteboard stringForType: NSFilenamesPboardType] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if( !PBoardString )
    {
        return nil;
    }
    //This gives you a plist style string with your filename that looks like this:
    /* <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
     <plist version="1.0">
     <array>
     <string>/Users/liupeng/Documents/workspace/GitHub/iTerm2</string>
     </array>
     </plist>  */
    const char* pboardcstring = [PBoardString UTF8String];
    if( !pboardcstring )
    {
         return nil;
    }
    NSInteger   len = strlen(pboardcstring);
    NSData* plistData = [[NSData alloc] initWithBytes:pboardcstring length:len];
    NSPropertyListReadOptions read_options = 0;
    NSError* deserializationError = NULL;
    NSArray* fileArray = (NSArray*)[NSPropertyListSerialization propertyListWithData:plistData options:read_options format:nil error:&deserializationError];
    if( deserializationError )
    {
        return nil;
    }
    return fileArray;
}
@end
