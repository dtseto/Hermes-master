#import <XCTest/XCTest.h>

typedef BOOL (*HMSInputMonitoringAccessFunction)(void);
extern void HMSSetListenEventAccessFunctionPointers(HMSInputMonitoringAccessFunction preflight,
                                                    HMSInputMonitoringAccessFunction request);

@interface PlaybackController : NSObject
- (BOOL)requestInputMonitoringAccessIfNeeded;
- (void)presentInputMonitoringInstructions;
@end

static BOOL gPreflightGranted = NO;
static BOOL TestPreflight(void) {
  return gPreflightGranted;
}

static BOOL TestRequestGrant(void) {
  gPreflightGranted = YES;
  return YES;
}

static BOOL TestRequestDeny(void) {
  gPreflightGranted = NO;
  return NO;
}

@interface PermissionTestPlaybackController : PlaybackController
@property(nonatomic, assign) NSUInteger instructionsCount;
@end

@implementation PermissionTestPlaybackController
- (void)presentInputMonitoringInstructions {
  self.instructionsCount += 1;
}
@end

@interface MediaPermissionTests : XCTestCase
@end

@implementation MediaPermissionTests

- (void)tearDown {
  gPreflightGranted = NO;
  HMSSetListenEventAccessFunctionPointers(NULL, NULL);
  [super tearDown];
}

- (void)testRequestSkipsWhenAlreadyGranted {
  if (@available(macOS 10.15, *)) {
    gPreflightGranted = YES;
    HMSSetListenEventAccessFunctionPointers(TestPreflight, TestRequestDeny);
    PermissionTestPlaybackController *controller = [[PermissionTestPlaybackController alloc] init];

    BOOL granted = [controller requestInputMonitoringAccessIfNeeded];

    XCTAssertTrue(granted);
    XCTAssertEqual(controller.instructionsCount, 0U);
  }
}

- (void)testRequestSucceedsWhenPromptGrantsAccess {
  if (@available(macOS 10.15, *)) {
    gPreflightGranted = NO;
    HMSSetListenEventAccessFunctionPointers(TestPreflight, TestRequestGrant);
    PermissionTestPlaybackController *controller = [[PermissionTestPlaybackController alloc] init];

    BOOL granted = [controller requestInputMonitoringAccessIfNeeded];

    XCTAssertTrue(granted);
    XCTAssertEqual(controller.instructionsCount, 0U);
  }
}

- (void)testRequestShowsInstructionsWhenPermissionDenied {
  if (@available(macOS 10.15, *)) {
    gPreflightGranted = NO;
    HMSSetListenEventAccessFunctionPointers(TestPreflight, TestRequestDeny);
    PermissionTestPlaybackController *controller = [[PermissionTestPlaybackController alloc] init];

    BOOL granted = [controller requestInputMonitoringAccessIfNeeded];

    XCTAssertFalse(granted);
    XCTAssertEqual(controller.instructionsCount, 1U);
  }
}

@end
