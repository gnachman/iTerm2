//
//  iTermAutomaticProfileSwitcherTest.m
//  iTerm2
//
//  Created by George Nachman on 2/28/16.
//
//

#import <XCTest/XCTest.h>
#import "ITAddressBookMgr.h"
#import "iTermAutomaticProfileSwitcher.h"
#import "NSDictionary+Profile.h"

@interface iTermAutomaticProfileSwitcherTest : XCTestCase<iTermAutomaticProfileSwitcherDelegate>

@end

@implementation iTermAutomaticProfileSwitcherTest {
    iTermAutomaticProfileSwitcher *_aps;
    iTermSavedProfile *_savedProfile;
    Profile *_profile;
    NSArray *_allProfiles;
    NSInteger _callsToLoadProfile;
}

- (Profile *)profileHostA {
    return @{ KEY_NAME: @"host=a", KEY_GUID: @"1", KEY_BOUND_HOSTS: @[ @"a" ] };
}

- (Profile *)profileHostB {
    return @{ KEY_NAME: @"host=b", KEY_GUID: @"2", KEY_BOUND_HOSTS: @[ @"b" ] };
}

- (Profile *)profilePathDir1 {
    return @{ KEY_NAME: @"path=dir1", KEY_GUID: @"3", KEY_BOUND_HOSTS: @[ @"/dir1" ] };
}

- (Profile *)profilePathDir1AndSubs {
    return @{ KEY_NAME: @"path=dir1AndSubs", KEY_GUID: @"3", KEY_BOUND_HOSTS: @[ @"/dir1/*" ] };
}

- (Profile *)profilePathDir2 {
    return @{ KEY_NAME: @"path=dir2", KEY_GUID: @"4", KEY_BOUND_HOSTS: @[ @"/dir2" ] };
}

- (Profile *)profileUserX {
    return @{ KEY_NAME: @"user=x", KEY_GUID: @"5", KEY_BOUND_HOSTS: @[ @"x@" ] };
}

- (Profile *)profileUserY {
    return @{ KEY_NAME: @"user=y", KEY_GUID: @"6", KEY_BOUND_HOSTS: @[ @"y@" ] };
}

- (Profile *)profileUserGeorgeHostItermPathHome {
    return @{ KEY_NAME: @"user=george host=iterm2.com path=home",
              KEY_GUID: @"7",
              KEY_BOUND_HOSTS: @[ @"george@iterm2.com:/home" ] };
}

- (Profile *)profileUserGeorgePathHome {
    return @{ KEY_NAME: @"user=george path=home",
              KEY_GUID: @"8",
              KEY_BOUND_HOSTS: @[ @"george@:/home" ] };
}

- (Profile *)profileUserGeorgeHostIterm {
    return @{ KEY_NAME: @"user=george host=iterm2.com",
              KEY_GUID: @"9",
              KEY_BOUND_HOSTS: @[ @"george@iterm2.com" ] };
}

- (Profile *)profileHostItermPathHome {
    return @{ KEY_NAME: @"host=iterm2.com path=home",
              KEY_GUID: @"10",
              KEY_BOUND_HOSTS: @[ @"iterm2.com:/home" ] };
}

- (Profile *)profileHostIterm {
    return @{ KEY_NAME: @"host=iterm2.com", KEY_GUID: @"11", KEY_BOUND_HOSTS: @[ @"iterm2.com" ] };
}

- (Profile *)profileUserGeorge {
    return @{ KEY_NAME: @"user=george", KEY_GUID: @"12", KEY_BOUND_HOSTS: @[ @"george@" ] };
}

- (Profile *)profilePathHome {
    return @{ KEY_NAME: @"path=home", KEY_GUID: @"13", KEY_BOUND_HOSTS: @[ @"/home" ] };
}

- (Profile *)profileHostAllDotCom {
    return @{ KEY_NAME: @"host=*.com", KEY_GUID: @"14", KEY_BOUND_HOSTS: @[ @"*.com" ] };
}

- (Profile *)profileAllPaths {
    return @{ KEY_NAME: @"path=/*", KEY_GUID: @"15", KEY_BOUND_HOSTS: @[ @"/*" ] };
}

- (void)setUp {
    [super setUp];
    _callsToLoadProfile = 0;
    _aps = [[iTermAutomaticProfileSwitcher alloc] initWithDelegate:self];

    _profile = _allProfiles[0];
}

- (void)tearDown {
    [_aps release];
    [_savedProfile release];
    [super tearDown];
}


#pragma mark - Tests

#pragma mark Various kinds of rules cause a profile switch

- (void)testSwitchesOnHostName {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileHostA, self.profileHostB ];
    [_aps setHostname:@"b" username:@"whatever" path:@"whatever"];
    XCTAssert([_profile isEqualToProfile:self.profileHostB]);
}

- (void)testSwitchesOnUserName {
    _profile = self.profileUserX;
    _allProfiles = @[ self.profileUserX, self.profileUserY ];
    [_aps setHostname:@"whatever" username:@"y" path:@"whatever"];
    XCTAssert([_profile isEqualToProfile:self.profileUserY]);
}

- (void)testSwitchesOnPath {
    _profile = self.profilePathDir1;
    _allProfiles = @[ self.profilePathDir1, self.profilePathDir2 ];
    [_aps setHostname:@"whatever" username:@"whatever" path:@"/dir2"];
    XCTAssert([_profile isEqualToProfile:self.profilePathDir2]);
}

- (void)testSwitchesOnWildcard {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileHostA, self.profileHostAllDotCom ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/home"];
    XCTAssert([_profile isEqualToProfile:self.profileHostAllDotCom]);
}

#pragma mark Priority is correct
// Host > User > Path

- (void)testUsernameHostnamePathOutranksUsernameHostname {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileUserGeorgeHostItermPathHome, self.profileUserGeorgeHostIterm ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/home"];
    XCTAssert([_profile isEqualToProfile:self.profileUserGeorgeHostItermPathHome]);
}

- (void)testUsernameHostnameOutranksUsernamePath {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileUserGeorgeHostIterm, self.profileUserGeorgePathHome ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/home"];
    XCTAssert([_profile isEqualToProfile:self.profileUserGeorgeHostIterm]);
}

- (void)testHostnamePathOutranksUsernamePath {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileHostItermPathHome, self.profileUserGeorgePathHome ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/home"];
    XCTAssert([_profile isEqualToProfile:self.profileHostItermPathHome]);
}

- (void)testHostnamePathOutranksHostname {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileHostItermPathHome, self.profileHostIterm ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/home"];
    XCTAssert([_profile isEqualToProfile:self.profileHostItermPathHome]);
}

- (void)testHostnameOutranksUsername {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileHostIterm, self.profileUserGeorge ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/home"];
    XCTAssert([_profile isEqualToProfile:self.profileHostIterm]);
}

- (void)testUsernameOutranksPath {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileUserGeorge, self.profilePathHome ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/home"];
    XCTAssert([_profile isEqualToProfile:self.profileUserGeorge]);
}

- (void)testExactHostnameOutranksWildcard {
    _profile = self.profileHostA;
    _allProfiles = @[ self.profileHostIterm, self.profileHostAllDotCom ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/home"];
    XCTAssert([_profile isEqualToProfile:self.profileHostIterm]);
}

#pragma mark Profile stack works

// Regression test for issue 4581. Don't switch away from the current profile
// to something on the stack if it still matches.
- (void)testPreferSpecificRuleEvenIfStackHasMatch {
    _profile = [self profileAllPaths];
    _allProfiles = @[ [self profileAllPaths],
                      [self profilePathDir1AndSubs] ];
    
    [_aps setHostname:@"iterm2.com"
             username:@"george"
                 path:@"/"];
    XCTAssert([_profile isEqualToProfile:[self profileAllPaths]]);
    
    [_aps setHostname:@"iterm2.com"
             username:@"george"
                 path:@"/dir1/foo"];
    XCTAssert([_profile isEqualToProfile:[self profilePathDir1AndSubs]]);
    
    [_aps setHostname:@"iterm2.com"
             username:@"george"
                 path:@"/dir1/foo/temp"];
    XCTAssert([_profile isEqualToProfile:[self profilePathDir1AndSubs]]);
}

// Restore to profile in middle of stack
- (void)testWalkUpStack {
    _profile = [self profileHostIterm];
    _allProfiles = @[ [self profileHostIterm],
                      [self profileUserGeorgeHostIterm],
                      [self profileUserGeorgeHostItermPathHome] ];
    [_aps setHostname:@"iterm2.com"
             username:@"george"
                 path:@"bogus path"];
    // stack is now: iterm2.com, george@iterm2.com
    [_aps setHostname:@"iterm2.com"
             username:@"george"
                 path:@"/home"];
    // stack is now: iterm2.com, george@iterm2.com, george@iterm2.com:/home
    [_aps setHostname:@"iterm2.com"
             username:@"george"
                 path:@"bogus path"];
    // If we didn't walk the stack all the way back up we should be on george@iterm2.com
    XCTAssert([_profile isEqualToProfile:[self profileUserGeorgeHostIterm]]);
}

// No change in configuration->No delegate call to load profile
- (void)testDontChangeProfileIfSame {
    _profile = [self profileHostIterm];
    _allProfiles = @[ [self profileHostIterm], [self profilePathDir1] ];
    [_aps setHostname:@"iterm2.com" username:@"george" path:@"/"];
    XCTAssertEqual(0, _callsToLoadProfile);
}

// Restores first in stack when nothing matches
- (void)testRestoreOriginalProfileWhenNothingMatches {
    _profile = [self profileHostIterm];
    _allProfiles = @[ [self profileHostIterm],
                      [self profileUserGeorgeHostIterm],
                      [self profileUserGeorgeHostItermPathHome] ];
    [_aps setHostname:@"iterm2.com"
             username:@"george"
                 path:@"bogus path"];
    // stack is now: iterm2.com, george@iterm2.com
    [_aps setHostname:@"iterm2.com"
             username:@"george"
                 path:@"/home"];
    // stack is now: iterm2.com, george@iterm2.com, george@iterm2.com:/home
    [_aps setHostname:@"qwerty"
             username:@"uiop"
                 path:@"asdf"];
    // Revert to initial profile.
    XCTAssert([_profile isEqualToProfile:[self profileHostIterm]]);
}

// Verify that creating an APS from saved state gives correct behavior.
- (void)testSaveAndRestore {
    NSDictionary *state = _aps.savedState;
    iTermAutomaticProfileSwitcher *aps2 =
        [[[iTermAutomaticProfileSwitcher alloc] initWithDelegate:self savedState:state] autorelease];
    XCTAssertEqualObjects(state, aps2.savedState);
    XCTAssertEqualObjects(_aps.profileStackString, aps2.profileStackString);
    
    
    // Check that the stack is good.
    _profile = [self profileHostIterm];
    _allProfiles = @[ [self profileHostIterm],
                      [self profileUserGeorgeHostIterm],
                      [self profileUserGeorgeHostItermPathHome] ];
    [aps2 setHostname:@"iterm2.com"
             username:@"george"
                 path:@"bogus path"];
    // stack is now: iterm2.com, george@iterm2.com
    XCTAssert([_profile isEqualToProfile:[self profileUserGeorgeHostIterm]]);
    
    [aps2 setHostname:@"iterm2.com"
             username:@"george"
                 path:@"/home"];
    // stack is now: iterm2.com, george@iterm2.com, george@iterm2.com:/home
    XCTAssert([_profile isEqualToProfile:[self profileUserGeorgeHostItermPathHome]]);
    
    // Pop one level
    [aps2 setHostname:@"iterm2.com" username:@"george" path:@"asdf"];
    // stack is now: iterm2.com, george@iterm2.com
    XCTAssert([_profile isEqualToProfile:[self profileUserGeorgeHostIterm]]);

    // Back to initial profile
    [aps2 setHostname:@"qwerty"
             username:@"uiop"
                 path:@"asdf"];
    // stack is now: iterm2.com
    XCTAssert([_profile isEqualToProfile:[self profileHostIterm]]);
}

#pragma mark - iTermAutomaticProfileSwitcherDelegate

- (void)automaticProfileSwitcherLoadProfile:(iTermSavedProfile *)savedProfile {
    ++_callsToLoadProfile;
    _profile = savedProfile.originalProfile;
}

- (Profile *)automaticProfileSwitcherCurrentProfile {
    return _profile;
}

- (iTermSavedProfile *)automaticProfileSwitcherCurrentSavedProfile {
    iTermSavedProfile *savedProfile = [[[iTermSavedProfile alloc] init] autorelease];
    savedProfile.originalProfile = _profile;
    savedProfile.profile = _profile;
    return savedProfile;
}

- (NSArray<Profile *> *)automaticProfileSwitcherAllProfiles {
    return _allProfiles;
}

@end
