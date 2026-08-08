#import <XCTest/XCTest.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "ArtworkButton.h"
#import "PlaybackSplitView.h"
#import "PreferencesController.h"

@class Song;
@class Station;
@class Pandora;

@interface PlaybackController : NSObject
@property(nonatomic, readonly) MPRemoteCommandCenter *remoteCommandCenter;
- (BOOL)play;
- (BOOL)pause;
- (void)playpause:(id)sender;
- (void)like:(id)sender;
- (void)dislike:(id)sender;
- (void)tired:(id)sender;
- (void)next:(id)sender;
- (void)toggleSongInfo:(id)sender;
- (void)toggleHistoryPanel;
- (void)restoreSongInfoVisibility;
- (void)startUpdatingProgress;
- (void)stopUpdatingProgress;
- (void)configureRemoteCommands;
@end


@interface Pandora : NSObject
@end

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
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:SONG_INFO_VISIBLE];
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
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:SONG_INFO_VISIBLE];
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

- (void)testSongInfoButtonTogglesExplanationVisibility {
  TestPlaybackController *controller = [[TestPlaybackController alloc] init];
  NSTextField *explanationLabel = [NSTextField labelWithString:@"Chosen for: acoustic vibe."];
  NSToolbarItem *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"songInfo"];
  [controller setValue:explanationLabel forKey:@"explanationLabel"];
  [controller setValue:toolbarItem forKey:@"songInfoToolbarItem"];
  explanationLabel.hidden = YES;

  [controller toggleSongInfo:nil];

  XCTAssertFalse(explanationLabel.hidden);
  XCTAssertTrue([[NSUserDefaults standardUserDefaults] boolForKey:SONG_INFO_VISIBLE]);
  XCTAssertEqualObjects(toolbarItem.toolTip, @"Hide why this song was chosen");

  [controller toggleSongInfo:nil];

  XCTAssertTrue(explanationLabel.hidden);
  XCTAssertFalse([[NSUserDefaults standardUserDefaults] boolForKey:SONG_INFO_VISIBLE]);
  XCTAssertEqualObjects(toolbarItem.toolTip, @"Show why this song was chosen");
}

- (void)testSongInfoVisibilityRestoresTheLastStateAndDefaultsHidden {
  TestPlaybackController *controller = [[TestPlaybackController alloc] init];
  NSTextField *explanationLabel = [NSTextField labelWithString:@"Chosen for: acoustic vibe."];
  NSToolbarItem *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"songInfo"];
  [controller setValue:explanationLabel forKey:@"explanationLabel"];
  [controller setValue:toolbarItem forKey:@"songInfoToolbarItem"];

  [controller restoreSongInfoVisibility];
  XCTAssertTrue(explanationLabel.hidden);

  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SONG_INFO_VISIBLE];
  [controller restoreSongInfoVisibility];
  XCTAssertFalse(explanationLabel.hidden);

  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:SONG_INFO_VISIBLE];
  [controller restoreSongInfoVisibility];
  XCTAssertTrue(explanationLabel.hidden);
}

- (void)testHistoryButtonTogglesPanelWithoutResizingWindow {
  TestPlaybackController *controller = [[TestPlaybackController alloc] init];
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 640, 420)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  NSView *playbackView = [[NSView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:playbackView];

  PlaybackSplitView *splitView =
      [[PlaybackSplitView alloc] initWithFrame:playbackView.bounds];
  NSView *stationsPanel = [[NSView alloc] initWithFrame:NSZeroRect];
  NSView *songColumn = [[NSView alloc] initWithFrame:NSZeroRect];
  NSStackView *historyPanel = [[NSStackView alloc] initWithFrame:NSZeroRect];
  splitView.preferredLeadingPaneWidth = 198.0;
  splitView.preferredTrailingPaneWidth = 173.0;
  [splitView setLeadingPane:stationsPanel
                 centerPane:songColumn
               trailingPane:historyPanel];
  [playbackView addSubview:splitView];

  [controller setValue:playbackView forKey:@"playbackView"];
  [controller setValue:historyPanel forKey:@"historyPanel"];
  [controller setValue:splitView forKey:@"playbackSplitView"];
  [controller setValue:@YES forKey:@"historyPanelVisible"];

  NSRect originalFrame = window.frame;
  CGFloat songWidthWithHistory = NSWidth(songColumn.frame);
  [controller toggleHistoryPanel];

  XCTAssertFalse([[controller valueForKey:@"historyPanelVisible"] boolValue]);
  XCTAssertTrue(historyPanel.hidden);
  XCTAssertGreaterThan(NSWidth(songColumn.frame), songWidthWithHistory);
  XCTAssertTrue(NSEqualRects(window.frame, originalFrame));

  [controller toggleHistoryPanel];

  XCTAssertTrue([[controller valueForKey:@"historyPanelVisible"] boolValue]);
  XCTAssertFalse(historyPanel.hidden);
  XCTAssertEqualWithAccuracy(NSWidth(historyPanel.frame), 173.0, 0.01);
  XCTAssertTrue(NSEqualRects(window.frame, originalFrame));
}

- (void)testArtworkImageNeverDefinesTheContainerLayoutSize {
  ArtworkContainerView *container =
      [[ArtworkContainerView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
  ArtworkButton *artwork = [[ArtworkButton alloc] initWithFrame:NSZeroRect];
  artwork.translatesAutoresizingMaskIntoConstraints = NO;
  [container addSubview:artwork];
  NSImage *largeImage = [[NSImage alloc] initWithSize:NSMakeSize(2400.0, 2400.0)];
  artwork.image = largeImage;
  [container layoutSubtreeIfNeeded];

  XCTAssertEqualObjects(artwork.image, largeImage);
  XCTAssertTrue(NSEqualSizes(container.fittingSize, NSZeroSize));
  XCTAssertEqualWithAccuracy(NSWidth(artwork.frame), 120.0, 0.5);
  XCTAssertEqualWithAccuracy(NSHeight(artwork.frame), 120.0, 0.5);
}

- (void)testPlaybackSplitViewOwnsPaneSizesDownToZeroWidth {
  PlaybackSplitView *splitView =
      [[PlaybackSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 900.0, 700.0)];
  NSView *stations = [[NSView alloc] initWithFrame:NSZeroRect];
  ArtworkContainerView *center = [[ArtworkContainerView alloc] initWithFrame:NSZeroRect];
  NSView *history = [[NSView alloc] initWithFrame:NSZeroRect];
  ArtworkButton *artwork = [[ArtworkButton alloc] initWithFrame:NSZeroRect];
  artwork.image = [[NSImage alloc] initWithSize:NSMakeSize(2400.0, 2400.0)];
  [center addSubview:artwork];

  [splitView setLeadingPane:stations centerPane:center trailingPane:history];
  XCTAssertTrue(NSEqualSizes(splitView.fittingSize, NSZeroSize));
  XCTAssertEqualWithAccuracy(NSWidth(stations.frame), 198.0, 0.5);
  XCTAssertEqualWithAccuracy(NSWidth(history.frame), 198.0, 0.5);
  XCTAssertGreaterThan(NSWidth(center.frame), 0.0);

  [splitView setFrameSize:NSMakeSize(300.0, 700.0)];
  XCTAssertEqualWithAccuracy(NSWidth(center.frame), 0.0, 0.5);
  XCTAssertLessThan(NSWidth(stations.frame), 198.0);
  XCTAssertLessThan(NSWidth(history.frame), 198.0);
  XCTAssertLessThanOrEqual(NSMaxX(history.frame), NSWidth(splitView.bounds) + 0.5);

  splitView.leadingPaneVisible = NO;
  splitView.trailingPaneVisible = NO;
  [splitView setFrameSize:NSMakeSize(1.0, 160.0)];
  [center layoutSubtreeIfNeeded];
  XCTAssertEqualWithAccuracy(NSWidth(center.frame), 1.0, 0.5);
  XCTAssertEqualWithAccuracy(NSWidth(artwork.frame), 1.0, 0.5);

  [splitView setFrameSize:NSMakeSize(0.0, 160.0)];
  [center layoutSubtreeIfNeeded];
  XCTAssertEqualWithAccuracy(NSWidth(center.frame), 0.0, 0.5);
  XCTAssertEqualWithAccuracy(NSWidth(artwork.frame), 0.0, 0.5);
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

- (void)testPlayPauseStartsWhenPlaybackIsNotActive {
  StubPlaying *playing = [[StubPlaying alloc] init];
  TestPlaybackController *controller = [self controllerWithPlaying:playing
                                                           pandora:[[StubPandora alloc] init]];

  [controller playpause:nil];

  XCTAssertTrue(playing.playInvoked);
  XCTAssertFalse(playing.pauseInvoked);
}

- (void)testPlayPausePausesActivePlayback {
  StubPlaying *playing = [[StubPlaying alloc] init];
  playing.currentlyPlaying = YES;
  TestPlaybackController *controller = [self controllerWithPlaying:playing
                                                           pandora:[[StubPandora alloc] init]];

  [controller playpause:nil];

  XCTAssertTrue(playing.pauseInvoked);
  XCTAssertFalse(playing.playInvoked);
}

- (void)testNativeMediaCommandsAreEnabled {
  TestPlaybackController *controller = [[TestPlaybackController alloc] init];

  [controller configureRemoteCommands];

  XCTAssertNotNil(controller.remoteCommandCenter);
  XCTAssertTrue(controller.remoteCommandCenter.playCommand.enabled);
  XCTAssertTrue(controller.remoteCommandCenter.pauseCommand.enabled);
  XCTAssertTrue(controller.remoteCommandCenter.togglePlayPauseCommand.enabled);
  XCTAssertTrue(controller.remoteCommandCenter.nextTrackCommand.enabled);
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
