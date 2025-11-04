#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "PreferencesController.h"

@class Song;
@class Station;
@class Pandora;

@interface PlaybackController : NSObject
- (BOOL)play;
- (BOOL)pause;
- (void)like:(id)sender;
- (void)dislike:(id)sender;
- (void)tired:(id)sender;
- (void)next:(id)sender;
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
@property(nonatomic, copy) NSString *art;
@property(nonatomic, copy) NSString *title;
@end

static NSMutableArray<NSString *> *gCancelledArt = nil;
static id gStubImageLoader = nil;
static id StubImageLoaderLoader(id self, SEL _cmd);

@interface ImageLoader : NSObject
+ (instancetype)loader;
- (void)cancel:(NSString *)url;
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

@interface StubImageLoader : NSObject
@end

@implementation StubImageLoader
- (void)loadImageURL:(NSString *)url callback:(void (^)(NSData *))callback {
  if (callback) {
    callback(nil);
  }
}
- (void)cancel:(NSString *)url {
  if (url != nil) {
    if (gCancelledArt != nil) {
      [gCancelledArt addObject:url];
    }
  }
}
@end

static id StubImageLoaderLoader(id self, SEL _cmd) {
  if (gStubImageLoader == nil) {
    gStubImageLoader = [[StubImageLoader alloc] init];
  }
  return gStubImageLoader;
}

@interface PlaybackControllerTests : XCTestCase
@property(nonatomic, assign) IMP originalImageLoaderLoaderIMP;
@property(nonatomic, strong) StubImageLoader *stubLoader;
@end

@implementation PlaybackControllerTests

- (void)setUp {
  [super setUp];
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:INPUT_MONITORING_REMINDER_ENABLED];
  gCancelledArt = [NSMutableArray array];
  self.stubLoader = [[StubImageLoader alloc] init];
  gStubImageLoader = self.stubLoader;
  Class loaderClass = NSClassFromString(@"ImageLoader");
  Method loaderMethod = class_getClassMethod(loaderClass, @selector(loader));
  self.originalImageLoaderLoaderIMP = method_getImplementation(loaderMethod);
  if (self.originalImageLoaderLoaderIMP != NULL) {
    method_setImplementation(loaderMethod, (IMP)StubImageLoaderLoader);
  }
}

- (void)tearDown {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:INPUT_MONITORING_REMINDER_ENABLED];
  Class loaderClass = NSClassFromString(@"ImageLoader");
  Method loaderMethod = class_getClassMethod(loaderClass, @selector(loader));
  if (self.originalImageLoaderLoaderIMP != NULL) {
    method_setImplementation(loaderMethod, self.originalImageLoaderLoaderIMP);
  }
  gStubImageLoader = nil;
  gCancelledArt = nil;
  self.stubLoader = nil;
  [super tearDown];
}

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

- (void)testNextCancelsArtAndAdvancesPlaying {
  StubPlaying *playing = [[StubPlaying alloc] init];
  TestSong *song = [self testSongWithRating:0 shared:NO];
  song.art = @"http://example.com/art.png";
  playing.currentSong = song;
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  [controller next:nil];

  XCTAssertTrue(playing.nextInvoked);
  XCTAssertNotNil(gCancelledArt);
  XCTAssertTrue([gCancelledArt containsObject:song.art]);
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
  if (weakTimer == nil) {
    return; // Timer already torn down with the controller.
  }
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  XCTAssertFalse([weakTimer isValid]);
}

- (void)testArtAccessibilityDescriptionMatchesSongTitle {
  StubPlaying *playing = [[StubPlaying alloc] init];
  TestSong *song = [self testSongWithRating:0 shared:NO];
  song.title = @"Test Title";
  playing.currentSong = song;
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  NSImageView *fakeArtView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
  [controller setValue:fakeArtView forKey:@"art"];

  NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(10, 10)];
  SEL setter = NSSelectorFromString(@"setArtImage:");
  if ([controller respondsToSelector:setter]) {
    ((void (*)(id, SEL, id))objc_msgSend)(controller, setter, image);
  }

  NSImageView *artView = [controller valueForKey:@"art"];
  XCTAssertEqualObjects(artView.toolTip, song.title);
  XCTAssertEqualObjects(image.accessibilityDescription, song.title);

  if ([controller respondsToSelector:setter]) {
    ((void (*)(id, SEL, id))objc_msgSend)(controller, setter, nil);
  }
  XCTAssertNil(artView.toolTip);
}

- (void)testPauseAndResumeOnScreenLockNotifications {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentlyPlaying = YES;
  StubPandora *pandora = [[StubPandora alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing pandora:pandora];

  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"pauseOnScreenLock"];
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"playOnScreenUnlock"];

  SEL pauseSelector = NSSelectorFromString(@"pauseOnScreenLock:");
  SEL unlockSelector = NSSelectorFromString(@"playOnScreenUnlock:");
  if ([controller respondsToSelector:pauseSelector]) {
    ((void (*)(id, SEL, id))objc_msgSend)(controller, pauseSelector, nil);
  }
  XCTAssertFalse(playing.currentlyPlaying);
  XCTAssertTrue([[controller valueForKey:@"pausedByScreenLock"] boolValue]);

  if ([controller respondsToSelector:unlockSelector]) {
    ((void (*)(id, SEL, id))objc_msgSend)(controller, unlockSelector, nil);
  }
  XCTAssertTrue(playing.playInvoked);
  XCTAssertFalse([[controller valueForKey:@"pausedByScreenLock"] boolValue]);
}

@end
