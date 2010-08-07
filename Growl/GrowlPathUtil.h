//
//  GrowlPathUtil.h
//  Growl
//
//  Created by Ingmar Stein on 17.04.05.
//  Copyright 2005 The Growl Project. All rights reserved.
//
// This file is under the BSD License, refer to License.txt for details

#import <Cocoa/Cocoa.h>

@interface GrowlPathUtil : NSObject {

}
/*!
 *	@method growlPrefPaneBundle
 *	@abstract Returns the bundle containing Growl's PrefPane.
 *	@discussion Searches all installed PrefPanes for the Growl PrefPane.
 *	@result Returns an NSBundle if Growl's PrefPane is installed, nil otherwise
 */
+ (NSBundle *) growlPrefPaneBundle;
+ (NSBundle *) helperAppBundle;
+ (NSString *) growlSupportDir;

//the current screenshots directory: $HOME/Library/Application\ Support/Growl/Screenshots
+ (NSString *) screenshotsDirectory;
//returns e.g. @"Screenshot 1". you append your own pathname extension; it is guaranteed not to exist.
+ (NSString *) nextScreenshotName;

@end
