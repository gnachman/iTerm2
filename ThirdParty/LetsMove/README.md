LetsMove
========

A sample project that demonstrates how to move a running Mac OS X application to the Applications folder.

![Screenshot](http://i.imgur.com/euTRZiI.png)


Requirements
------------
Builds and runs on Mac OS X 10.6 or higher. Does NOT support sandboxed applications.


Usage
-----

Option 1:

Build then embed LetsMove.framework into your app.

Option 2:

Copy the following files into your project:

- PFMoveApplication.h
- PFMoveApplication.m

If your project has ARC enabled, you'll want to disable ARC on the above files. You can do so by adding -fno-objc-arc compiler flag to your PFMoveApplication.m source file. See http://stackoverflow.com/questions/6646052/how-can-i-disable-arc-for-a-single-file-in-a-project/6658549#6658549

If your application is localized, also copy the 'MoveApplication.string' files into your project.

Link your application against Security.framework.

In your app delegate's "-[applicationWillFinishLaunching:]" method, call the PFMoveToApplicationsFolderIfNecessary function at the very top.


License
-------
Public domain



Version History
---------------

* 1.21
	- Support for [Carthage](https://github.com/Carthage/Carthage) added
	- Project now support OS X 10.6 and higher

* 1.20
	- Support for applications bundled inside another application
	- Brazilian Portuguese localization slightly updated
	- Build warnings fixed

* 1.19
	- Slovak localization added

* 1.18
	- Catalan localization added

* 1.17
	- Tranditional Chinese localization added.

* 1.16
	- Deprecation warning that appears when minimum deployment target is set to OS X 10.10 taken care of

* 1.15
	- Swedish localization added

* 1.14
	- Hugarian, Serbian, and Turkish localizations added
	- Macedonian localization added

* 1.13
	- Polish localization added

* 1.12
	- Use country code based .lproj directories
	- Make it compile for projects that don't use precompiled headers to import AppKit.framework
	- Minor adjustment to Dutch localization
	- Warning fixes in example project

* 1.11
	- Objective-C++ compatibility

* 1.10
	- Fixed deprecation warnings that show up when building against the OS X 10.9 SDK.

* 1.9
	- Removed OS X 10.4 support
	- Properly detect if the running app is in a disk image
	- Fixed a bug where if the app's name contained a quote, the app could not be moved
	- After a successful move, delete the application instead of moving it to the Trash.
	- Other fixes and improvements

* 1.8
	- If the app is already there in the Applications folder but not writable, request authentication from user
	- Added Korean localization

* 1.7.2
	- Fixed an exception that could happen.

* 1.7.1
	- Refactoring

* 1.7
	- Only move to ~/Appilcations directory if an app is already in there.

* 1.6.3
	- Function calls deprecated in 10.7 no longer cause compile time warnings.
	- Added Simplified Chinese and European Portuguese localizations

* 1.6.2
	- Garbage collection compatibility added
	- Use a new method to check if an application is already running on Mac OS X 10.6 systems or higher

* 1.6.1
	- Use exit(0) to terminate the app before relaunching instead of [NSApp terminate:]. We don't want applicationShouldTerminate or applicationWillTerminate NSApplication delegate methods to be called, possibly introducing side effects.

* 1.6
	- Resolve any aliases when finding the Applications directory

* 1.5.2
	- Cleaned up the code a bit. Almost functionally equivalent to 1.5.1.

* 1.5.1
	- Fixed a bug with clearing the quarantine file attribute on Mac OS X 10.5

* 1.5
	- Don't prompt to move the application if it has "Applications" in its path somewhere

* 1.4
	- Mac OS X 10.5 compatibility fixes

* 1.3
	- Fixed a rare bug in the shell script that checks to see if the app is already running
	- Clear quarantine flag after copying
	- Compile time option to show normal sized alert supress checkbox button
	- German, Danish, and Norwegian localizations added

* 1.2
	- Copy application from disk image then unmount disk image
	- Spanish, French, Dutch, and Russian localizations

* 1.1
	- Prefers ~/Applications over /Applications if it exists
	- Escape key pushes the "Do Not Move" button

* 1.0
	- First release


Code Contributors:
-------------
* Andy Kim
* John Brayton
* Chad Sellers
* Kevin LaCoste
* Rasmus Andersson
* Timothy J. Wood
* Matt Gallagher
* Whitney Young
* Nick Moore
* Nicholas Riley
* Matt Prowse


Translators:
------------
* Eita Hayashi (Japanese)
* Gleb M. Borisov (Russian)
* Wouter Broekhof (Dutch)
* Rasmus Andersson / Spotify (French and Spanish)
* Markus Kirschner (German)
* Fredrik Nannestad (Danish)
* Georg Alexander Bøe (Norwegian)
* Marco Improda (Italian)
* Venj Chu (Simplified Chinese)
* Sérgio Miranda (European Portuguese)
* Victor Figueiredo and BR Lingo (Brazilian Portuguese)
* AppLingua (Korean)
* Czech X Team (Czech)
* Marek Telecki (Polish)
* Petar Vlahu (Macedonian)
* Václav Slavík (Hungarian, Serbian, and Turkish)
* Erik Vikström (Swedish)
* Inndy Lin (Traditional Chinese)
* aONe (Catalan)
* Marek Hrusovsky (Slovak)

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
