#import <XCTest/XCTest.h>

@class Song;
@class Station;
@class Pandora;

@interface PlaybackController : NSObject
- (BOOL)play;
- (BOOL)pause;
- (void)like:(id)sender;
- (void)dislike:(id)sender;
- (void)tired:(id)sender;
- (void)startUpdatingProgress;
- (void)stopUpdatingProgress;
@end

@interface Pandora : NSObject
@end

typedef BOOL (*HMSInputMonitoringAccessFunction)(void);
extern void HMSSetListenEventAccessFunctionPointers(HMSInputMonitoringAccessFunction preflight,
                                                    HMSInputMonitoringAccessFunction request);

@interface Song : NSObject
@property(nonatomic, retain) NSNumber *nrating;
@end

@interface StubStation : NSObject
@property(nonatomic, assign) BOOL shared;
@end
@implementation StubStation
@end

@interface TestSong : Song
@property(nonatomic, strong) StubStation *overrideStation;
@end
@implementation TestSong
- (Station *)station {
  return (Station *)self.overrideStation;
}
@end

@interface StubPlaying : NSObject
@property(nonatomic, assign) BOOL currentlyPlaying;
@property(nonatomic, assign) BOOL playInvoked;
@property(nonatomic, assign) BOOL pauseInvoked;
@property(nonatomic, assign) BOOL clearInvoked;
@property(nonatomic, strong) Song *currentSong;
@property(nonatomic, assign) BOOL nextInvoked;
@end
@implementation StubPlaying
- (BOOL)isPlaying {
  return self.currentlyPlaying;
}
- (void)play {
  self.playInvoked = YES;
  self.currentlyPlaying = YES;
}
- (void)pause {
  self.pauseInvoked = YES;
  self.currentlyPlaying = NO;
}
- (Song *)playingSong {
  return self.currentSong;
}
- (void)clearSongList {
  self.clearInvoked = YES;
}
- (void)next {
  self.nextInvoked = YES;
}
- (void)stop {
  self.currentlyPlaying = NO;
}
@end

@interface StubPandora : NSObject
@property(nonatomic, strong) Song *lastRatedSong;
@property(nonatomic, strong) NSNumber *lastRating;
@property(nonatomic, strong) Song *tiredSong;
@end
@implementation StubPandora
- (void)rateSong:(Song *)song as:(BOOL)liked {
  self.lastRatedSong = song;
  self.lastRating = @(liked);
}
- (void)deleteRating:(Song *)song {
  self.lastRatedSong = song;
  self.lastRating = @0;
}
- (void)tiredOfSong:(Song *)song {
  self.tiredSong = song;
}
@end

@interface TestPlaybackController : PlaybackController
@property(nonatomic, strong) StubPandora *testPandora;
@end
@implementation TestPlaybackController
- (Pandora *)pandora {
  return (Pandora *)self.testPandora;
}
@end

@interface PlaybackControllerTests : XCTestCase
@end

@implementation PlaybackControllerTests

- (TestPlaybackController *)controllerWithPlaying:(StubPlaying *)playing pandora:(StubPandora *)pandora {
  TestPlaybackController *controller = [[TestPlaybackController alloc] init];
  controller.testPandora = pandora;
  [controller setValue:playing forKey:@"playing"];
  return controller;
}

- (TestSong *)testSongWithRating:(NSInteger)rating shared:(BOOL)sharedFlag {
  TestSong *song = [[TestSong alloc] init];
  song.nrating = @(rating);
  StubStation *station = [[StubStation alloc] init];
  station.shared = sharedFlag;
  song.overrideStation = station;
  return song;
}

- (void)testPlayStartsWhenNotAlreadyPlaying {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentlyPlaying = NO;
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  BOOL didStart = [controller play];

  XCTAssertTrue(didStart);
  XCTAssertTrue(playing.playInvoked);
}

- (void)testPlayReturnsNoWhenAlreadyPlaying {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentlyPlaying = YES;
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  BOOL didStart = [controller play];

  XCTAssertFalse(didStart);
  XCTAssertFalse(playing.playInvoked);
}

- (void)testPauseStopsWhenPlaying {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentlyPlaying = YES;
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  BOOL didPause = [controller pause];

  XCTAssertTrue(didPause);
  XCTAssertTrue(playing.pauseInvoked);
}

- (void)testPauseReturnsNoWhenAlreadyPaused {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentlyPlaying = NO;
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  BOOL didPause = [controller pause];

  XCTAssertFalse(didPause);
  XCTAssertFalse(playing.pauseInvoked);
}

- (void)testLikeRatesSongPositive {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentSong = [self testSongWithRating:0 shared:NO];
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  [controller like:nil];

  XCTAssertEqualObjects(pandora.lastRatedSong, playing.currentSong);
  XCTAssertEqualObjects(pandora.lastRating, @YES);
}

- (void)testDislikeClearsQueueAndRatesNegative {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentSong = [self testSongWithRating:0 shared:NO];
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  [controller dislike:nil];

  XCTAssertTrue(playing.clearInvoked);
  XCTAssertTrue(playing.nextInvoked);
  XCTAssertEqualObjects(pandora.lastRatedSong, playing.currentSong);
  XCTAssertEqualObjects(pandora.lastRating, @NO);
}

- (void)testTiredRequestsPandoraWhenSongAvailable {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentSong = [self testSongWithRating:0 shared:NO];
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  [controller tired:nil];

  XCTAssertEqualObjects(pandora.tiredSong, playing.currentSong);
  XCTAssertTrue(playing.nextInvoked);
}

- (void)testProgressTimerInvalidatesOnDealloc {
  __weak NSTimer *weakTimer = nil;
  @autoreleasepool {
    TestPlaybackController *controller = [[TestPlaybackController alloc] init];
    [controller startUpdatingProgress];
    NSTimer *timer = [controller valueForKey:@"progressUpdateTimer"];
    XCTAssertNotNil(timer);
    weakTimer = timer;
    controller = nil;
  }
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  if (weakTimer != nil) {
    XCTAssertFalse([weakTimer isValid]);
  }
}

@end
