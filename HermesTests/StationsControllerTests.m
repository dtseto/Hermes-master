#import <XCTest/XCTest.h>

#import "PreferencesController.h"
#import "StationsController.h"
#import "Pandora/Station.h"

@interface StationsController ()
@property (nonatomic, assign) BOOL hasPresentedStationsView;
- (void)stationsLoaded:(NSNotification *)not;
@end

@interface StubPandoraForStations : NSObject
@property (nonatomic, strong) NSArray *stations;
@property (nonatomic, assign) NSInteger lastSortMode;
@property (nonatomic, assign) NSInteger sortCallCount;
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
  self.lastSortMode = mode;
  self.sortCallCount += 1;
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

- (void)setUp {
  [super setUp];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:SORT_STATIONS];
}

- (void)tearDown {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:SORT_STATIONS];
  [super tearDown];
}

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

- (void)testStationsLoadedDoesNotFlashChooserWhenSavedStationRestores {
  TestableStationsController *controller = [self makeController];
  controller.stubPlayingStation = nil;
  controller.playSavedStationResult = YES;

  [controller stationsLoaded:nil];

  XCTAssertFalse(controller.presentChooserCalled, @"Saved station restore should let playback take over without briefly flashing the chooser.");
  XCTAssertFalse(controller.hasPresentedStationsView);
}

- (void)testStationsLoadedDoesNotShowChooserWhenStationAlreadyActive {
  TestableStationsController *controller = [self makeController];
  controller.stubPlayingStation = [[Station alloc] init];

  [controller stationsLoaded:nil];

  XCTAssertFalse(controller.presentChooserCalled, @"Station reload should not replace active playback with the chooser.");
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

- (void)testSortStationsByNameActionSelectsAlphabeticalAscending {
  TestableStationsController *controller = [self makeController];
  [[NSUserDefaults standardUserDefaults] setInteger:SORT_DATE_ASC
                                             forKey:SORT_STATIONS];

  [controller sortStationsByName:nil];

  XCTAssertEqual([[NSUserDefaults standardUserDefaults] integerForKey:SORT_STATIONS], SORT_NAME_ASC);
  XCTAssertEqual(controller.stubPandora.lastSortMode, SORT_NAME_ASC);
  XCTAssertEqual(controller.stubPandora.sortCallCount, 1);
}

- (void)testSortStationsByDateActionSelectsDateAscending {
  TestableStationsController *controller = [self makeController];
  [[NSUserDefaults standardUserDefaults] setInteger:SORT_NAME_ASC
                                             forKey:SORT_STATIONS];

  [controller sortStationsByDate:nil];

  XCTAssertEqual([[NSUserDefaults standardUserDefaults] integerForKey:SORT_STATIONS], SORT_DATE_ASC);
  XCTAssertEqual(controller.stubPandora.lastSortMode, SORT_DATE_ASC);
  XCTAssertEqual(controller.stubPandora.sortCallCount, 1);
}

@end
