#import <XCTest/XCTest.h>

#import "StationsController.h"
#import "Pandora/Station.h"

@interface StationsController ()
@property (nonatomic, assign) BOOL hasPresentedStationsView;
- (void)stationsLoaded:(NSNotification *)not;
@end

@interface StubPandoraForStations : NSObject
@property (nonatomic, strong) NSArray *stations;
@end

@implementation StubPandoraForStations

- (instancetype)init {
  if ((self = [super init])) {
    _stations = @[];
  }
  return self;
}

- (NSArray *)stations {
  return _stations ?: @[];
}

- (void)sortStations:(NSInteger)mode {
  // No-op for tests; the controller only cares that the selector exists.
}

@end

@interface TestableStationsController : StationsController
@property (nonatomic, strong) StubPandoraForStations *stubPandora;
@property (nonatomic, strong) Station *stubPlayingStation;
@property (nonatomic, assign) BOOL playSavedStationResult;
@property (nonatomic, assign) BOOL presentChooserCalled;
@property (nonatomic, assign) BOOL presentChooserCalledOnMainThread;
@end

@implementation TestableStationsController

- (Pandora *)pandora {
  return (Pandora *)self.stubPandora;
}

- (Station *)playingStation {
  return self.stubPlayingStation;
}

- (BOOL)playSavedStation {
  return self.playSavedStationResult;
}

- (void)presentStationsChooser {
  self.presentChooserCalled = YES;
  self.presentChooserCalledOnMainThread = [NSThread isMainThread];
  self.hasPresentedStationsView = YES;
}

@end

@interface StationsControllerTests : XCTestCase
@end

@implementation StationsControllerTests

- (TestableStationsController *)makeController {
  TestableStationsController *controller = [[TestableStationsController alloc] init];
  controller.stubPandora = [[StubPandoraForStations alloc] init];
  controller.playSavedStationResult = NO;
  controller.presentChooserCalled = NO;
  controller.hasPresentedStationsView = NO;
  // Provide a dummy chooser view so setValue:forKey: succeeds.
  NSView *dummyView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
  [controller setValue:dummyView forKey:@"chooseStationView"];
  return controller;
}

- (void)testStationsLoadedShowsChooserWhenNoStationActive {
  TestableStationsController *controller = [self makeController];
  controller.stubPlayingStation = nil;
  controller.playSavedStationResult = NO;

  [controller stationsLoaded:nil];

  XCTAssertTrue(controller.presentChooserCalled, @"Chooser view should be presented when nothing is playing and no saved station restores.");
}

- (void)testStationsLoadedShowsChooserWhenSavedStationRestores {
  TestableStationsController *controller = [self makeController];
  controller.stubPlayingStation = nil;
  controller.playSavedStationResult = YES;

  [controller stationsLoaded:nil];

  XCTAssertTrue(controller.presentChooserCalled, @"Chooser view should be presented even when playSavedStation recovers playback.");
}

- (void)testStationsLoadedDoesNotReShowChooserOncePresentedAndStationActive {
  TestableStationsController *controller = [self makeController];
  controller.stubPlayingStation = [[Station alloc] init];
  controller.hasPresentedStationsView = YES;

  [controller stationsLoaded:nil];

  XCTAssertFalse(controller.presentChooserCalled, @"Chooser view should not flash again once already presented and playback is active.");
}

- (void)testStationsLoadedDispatchesToMainThreadWhenCalledInBackground {
  TestableStationsController *controller = [self makeController];
  controller.stubPlayingStation = nil;

  XCTestExpectation *expectation = [self expectationWithDescription:@"stationsLoaded on main"];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    [controller stationsLoaded:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
      [expectation fulfill];
    });
  });

  [self waitForExpectationsWithTimeout:1 handler:nil];

  XCTAssertTrue(controller.presentChooserCalled);
  XCTAssertTrue(controller.presentChooserCalledOnMainThread, @"UI work must occur on the main thread.");
}

@end
