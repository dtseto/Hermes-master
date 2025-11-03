#import <XCTest/XCTest.h>

#import "PreferencesController.h"

@interface PlaybackController : NSObject
@property BOOL pausedByScreensaver;
@property BOOL pausedByScreenLock;
- (BOOL)play;
- (BOOL)pause;
- (void)pauseOnScreensaverStart:(NSNotification *)note;
- (void)playOnScreensaverStop:(NSNotification *)note;
- (void)pauseOnScreenLock:(NSNotification *)note;
- (void)playOnScreenUnlock:(NSNotification *)note;
@end

@interface SleepLockPlaybackController : PlaybackController
@property(nonatomic) NSInteger playCallCount;
@property(nonatomic) NSInteger pauseCallCount;
@property(nonatomic) BOOL nextPlayResult;
@property(nonatomic) BOOL nextPauseResult;
@end

@implementation SleepLockPlaybackController

- (instancetype)init {
  if ((self = [super init])) {
    _nextPlayResult = YES;
    _nextPauseResult = YES;
  }
  return self;
}

- (BOOL)play {
  self.playCallCount += 1;
  return self.nextPlayResult;
}

- (BOOL)pause {
  self.pauseCallCount += 1;
  return self.nextPauseResult;
}

@end

@interface PlaybackSleepLockTests : XCTestCase
@property(nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation PlaybackSleepLockTests

- (void)setUp {
  [super setUp];
  self.defaults = [NSUserDefaults standardUserDefaults];
  NSArray<NSString *> *keys = @[
    PAUSE_ON_SCREENSAVER_START,
    PLAY_ON_SCREENSAVER_STOP,
    PAUSE_ON_SCREEN_LOCK,
    PLAY_ON_SCREEN_UNLOCK
  ];
  for (NSString *key in keys) {
    [self.defaults removeObjectForKey:key];
  }
}

- (void)tearDown {
  NSArray<NSString *> *keys = @[
    PAUSE_ON_SCREENSAVER_START,
    PLAY_ON_SCREENSAVER_STOP,
    PAUSE_ON_SCREEN_LOCK,
    PLAY_ON_SCREEN_UNLOCK
  ];
  for (NSString *key in keys) {
    [self.defaults removeObjectForKey:key];
  }
  [super tearDown];
}

- (void)testPauseOnScreensaverStartHonorsPreference {
  SleepLockPlaybackController *controller = [[SleepLockPlaybackController alloc] init];
  controller.nextPauseResult = YES;
  controller.pausedByScreensaver = NO;
  [self.defaults setBool:YES forKey:PAUSE_ON_SCREENSAVER_START];

  [controller pauseOnScreensaverStart:nil];

  XCTAssertEqual(controller.pauseCallCount, 1);
  XCTAssertTrue(controller.pausedByScreensaver);
}

- (void)testPauseOnScreensaverStartNoOpWhenPreferenceDisabled {
  SleepLockPlaybackController *controller = [[SleepLockPlaybackController alloc] init];
  controller.pausedByScreensaver = NO;
  [self.defaults setBool:NO forKey:PAUSE_ON_SCREENSAVER_START];

  [controller pauseOnScreensaverStart:nil];

  XCTAssertEqual(controller.pauseCallCount, 0);
  XCTAssertFalse(controller.pausedByScreensaver);
}

- (void)testPauseOnScreensaverStartKeepsFlagFalseIfPauseFails {
  SleepLockPlaybackController *controller = [[SleepLockPlaybackController alloc] init];
  controller.nextPauseResult = NO;
  controller.pausedByScreensaver = NO;
  [self.defaults setBool:YES forKey:PAUSE_ON_SCREENSAVER_START];

  [controller pauseOnScreensaverStart:nil];

  XCTAssertEqual(controller.pauseCallCount, 1);
  XCTAssertFalse(controller.pausedByScreensaver);
}

- (void)testPlayOnScreensaverStopResumesAndResetsFlag {
  SleepLockPlaybackController *controller = [[SleepLockPlaybackController alloc] init];
  controller.pausedByScreensaver = YES;
  [self.defaults setBool:YES forKey:PLAY_ON_SCREENSAVER_STOP];

  [controller playOnScreensaverStop:nil];

  XCTAssertEqual(controller.playCallCount, 1);
  XCTAssertFalse(controller.pausedByScreensaver);
}

- (void)testPlayOnScreensaverStopNoOpWithoutFlag {
  SleepLockPlaybackController *controller = [[SleepLockPlaybackController alloc] init];
  controller.pausedByScreensaver = NO;
  [self.defaults setBool:YES forKey:PLAY_ON_SCREENSAVER_STOP];

  [controller playOnScreensaverStop:nil];

  XCTAssertEqual(controller.playCallCount, 0);
  XCTAssertFalse(controller.pausedByScreensaver);
}

- (void)testPauseOnScreenLockRecordsState {
  SleepLockPlaybackController *controller = [[SleepLockPlaybackController alloc] init];
  controller.nextPauseResult = YES;
  controller.pausedByScreenLock = NO;
  [self.defaults setBool:YES forKey:PAUSE_ON_SCREEN_LOCK];

  [controller pauseOnScreenLock:nil];

  XCTAssertEqual(controller.pauseCallCount, 1);
  XCTAssertTrue(controller.pausedByScreenLock);
}

- (void)testPlayOnScreenUnlockResumesAndClearsFlag {
  SleepLockPlaybackController *controller = [[SleepLockPlaybackController alloc] init];
  controller.pausedByScreenLock = YES;
  [self.defaults setBool:YES forKey:PLAY_ON_SCREEN_UNLOCK];

  [controller playOnScreenUnlock:nil];

  XCTAssertEqual(controller.playCallCount, 1);
  XCTAssertFalse(controller.pausedByScreenLock);
}

- (void)testPlayOnScreenUnlockIgnoredWhenPreferenceOff {
  SleepLockPlaybackController *controller = [[SleepLockPlaybackController alloc] init];
  controller.pausedByScreenLock = YES;
  [self.defaults setBool:NO forKey:PLAY_ON_SCREEN_UNLOCK];

  [controller playOnScreenUnlock:nil];

  XCTAssertEqual(controller.playCallCount, 0);
  XCTAssertTrue(controller.pausedByScreenLock);
}

@end
