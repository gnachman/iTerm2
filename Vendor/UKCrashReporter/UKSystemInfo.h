//
//  UKSystemInfo.h
//  UKSystemInfo
//
//  Created by Uli Kusterer on 23.09.04.
//  Copyright 2004 M. Uli Kusterer. All rights reserved.
//

#import <Cocoa/Cocoa.h>


unsigned	UKPhysicalRAMSize(void);						// RAM Size in MBs.
NSString*	UKSystemVersionString(void);					// System version as a string MM.m.b
unsigned	UKClockSpeed(void);								// CPU speed in MHz.
unsigned	UKCountCores(void);								// Number of CPU cores. This is always >= number of CPUs.
NSString*	UKMachineName(void);							// Name of Mac model, as best as we can determine.
NSString*	UKCPUName(void);								// Same as UKAutoreleasedCPUName( NO );
NSString*	UKAutoreleasedCPUName( BOOL releaseIt );	// Returns CPU name, i.e. "G3", "G4" etc. If releaseIt is YES, this will look up the name anew each time, otherwise it will cache the name for subsequent calls. Doesn't support the G5 :-(
//NSString*	UKSystemSerialNumber();
void		UKGetSystemVersionComponents( SInt32* outMajor, SInt32* outMinor, SInt32* outBugfix );	// System version as the separate components (Major.Minor.Bugfix).

// Don't use the following for new code:
//	(Since the number is in BCD, the maximum for minor and bugfix revisions is 9, so this returns 1049 for 10.4.10)
unsigned int	UKSystemVersion(void);							// System version as BCD number, I.e. 0xMMmb
