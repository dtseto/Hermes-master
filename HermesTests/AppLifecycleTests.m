#import <XCTest/XCTest.h>

#import "HermesAppDelegate.h"
#import "PreferencesController.h"

@interface AppLifecycleTests : XCTestCase
@end

@implementation AppLifecycleTests

- (void)tearDown {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:STATUS_BAR_ICON];
  [super tearDown];
}

- (void)testClosingLastWindowKeepsHermesRunningWithStatusItemVisible {
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:STATUS_BAR_ICON];
  HermesAppDelegate *delegate = [[HermesAppDelegate alloc] init];

  XCTAssertFalse([delegate applicationShouldTerminateAfterLastWindowClosed:NSApp]);
}

- (void)testClosingLastWindowQuitsHermesWithoutStatusItem {
  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:STATUS_BAR_ICON];
  HermesAppDelegate *delegate = [[HermesAppDelegate alloc] init];

  XCTAssertTrue([delegate applicationShouldTerminateAfterLastWindowClosed:NSApp]);
}

@end
