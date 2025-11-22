#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "ASPlaylist.h"
#import "AudioStreamer.h"
#import "../Sources/AudioStreamer/AudioStreamer+Testing.h"

static AudioStreamer *(*OriginalStreamWithURL)(Class, SEL, NSURL *);
static NSMutableArray<AudioStreamer *> *gStreamerQueue = nil;
static BOOL gForceNonTransientErrors = NO;

static void EnqueueTestStreamer(AudioStreamer *streamer) {
  if (streamer == nil) {
    return;
  }
  if (gStreamerQueue == nil) {
    gStreamerQueue = [[NSMutableArray alloc] init];
  }
  [gStreamerQueue addObject:streamer];
}

static AudioStreamer *TestStreamWithURL(Class cls, SEL _cmd, NSURL *url) {
  if (gStreamerQueue.count > 0) {
    AudioStreamer *streamer = gStreamerQueue.firstObject;
    [gStreamerQueue removeObjectAtIndex:0];
    return streamer;
  }
  return OriginalStreamWithURL(cls, _cmd, url);
}

@interface TestPlaylistAudioStreamer : AudioStreamer
@property (nonatomic, assign) NSUInteger startInvocationCount;
@property (nonatomic, assign) NSUInteger autoFailCount;
@property (nonatomic, assign) AudioStreamerErrorCode forcedErrorCode;
@property (nonatomic, strong) XCTestExpectation *successExpectation;
@end

@implementation TestPlaylistAudioStreamer

- (instancetype)init {
  if ((self = [super init])) {
    _forcedErrorCode = AS_TIMED_OUT;
  }
  return self;
}

+ (BOOL)isErrorCodeTransient:(AudioStreamerErrorCode)errorCode
                networkError:(NSError *)networkError {
  if (gForceNonTransientErrors) {
    return NO;
  }
  return [AudioStreamer isErrorCodeTransient:errorCode networkError:networkError];
}

- (BOOL)openURLSession {
  ((void (*)(id, SEL, AudioStreamerState))objc_msgSend)(self, NSSelectorFromString(@"setState:"), AS_WAITING_FOR_DATA);
  return YES;
}

- (void)teardownAudioResources {
}

- (BOOL)start {
  self.startInvocationCount += 1;
  NSUInteger attempt = self.startInvocationCount;
  if (self.autoFailCount > 0 && attempt <= self.autoFailCount) {
    [self simulateErrorForTesting:self.forcedErrorCode];
    EnqueueTestStreamer(self);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      ((void (*)(id, SEL, AudioStreamerState))objc_msgSend)(self, NSSelectorFromString(@"setState:"), AS_PLAYING);
    });
    if (self.successExpectation != nil) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.successExpectation fulfill];
      });
    }
  }
  return YES;
}

@end

@interface ASPlaylistRetryTests : XCTestCase
@end

@implementation ASPlaylistRetryTests

+ (void)setUp {
  Class cls = objc_getClass("AudioStreamer");
  Method original = class_getClassMethod(cls, @selector(streamWithURL:));
  OriginalStreamWithURL = (AudioStreamer *(*)(Class, SEL, NSURL *))method_getImplementation(original);
  method_setImplementation(original, (IMP)TestStreamWithURL);
  gStreamerQueue = [[NSMutableArray alloc] init];
  gForceNonTransientErrors = NO;
}

+ (void)tearDown {
  Class cls = objc_getClass("AudioStreamer");
  Method original = class_getClassMethod(cls, @selector(streamWithURL:));
  method_setImplementation(original, (IMP)OriginalStreamWithURL);
  OriginalStreamWithURL = NULL;
  [gStreamerQueue removeAllObjects];
  gForceNonTransientErrors = NO;
}

- (void)testPlaylistIgnoresTransientErrorsDuringRetry {
  TestPlaylistAudioStreamer *streamer = [[TestPlaylistAudioStreamer alloc] init];
  streamer.autoFailCount = 1;
  streamer.successExpectation = [self expectationWithDescription:@"playlist recovered"];
  EnqueueTestStreamer(streamer);

  __block BOOL streamErrorObserved = NO;
  id token = [[NSNotificationCenter defaultCenter]
      addObserverForName:ASStreamError
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(__unused NSNotification *note) {
                streamErrorObserved = YES;
              }];

  ASPlaylist *playlist = [[ASPlaylist alloc] init];
  NSURL *url = [NSURL URLWithString:@"https://example.com/test.mp3"];
  [playlist addSong:url play:YES];

  [self waitForExpectations:@[streamer.successExpectation] timeout:3.0];
  [[NSNotificationCenter defaultCenter] removeObserver:token];
  XCTAssertFalse(streamErrorObserved);
  [playlist stop];
}

- (void)testPlaylistEmitsErrorAfterRetriesExhausted {
  gForceNonTransientErrors = YES;
  TestPlaylistAudioStreamer *streamer = [[TestPlaylistAudioStreamer alloc] init];
  streamer.autoFailCount = 4; // exceed default retry count
  EnqueueTestStreamer(streamer);

  XCTestExpectation *errorExpectation = [self expectationWithDescription:@"stream error notification"];
  id token = [[NSNotificationCenter defaultCenter]
      addObserverForName:ASStreamError
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(__unused NSNotification *note) {
                [errorExpectation fulfill];
              }];

  ASPlaylist *playlist = [[ASPlaylist alloc] init];
  NSURL *url = [NSURL URLWithString:@"https://example.com/test.mp3"];
  [playlist addSong:url play:YES];

  [self waitForExpectations:@[errorExpectation] timeout:3.0];
  gForceNonTransientErrors = NO;
  [[NSNotificationCenter defaultCenter] removeObserver:token];
  [playlist stop];
}

- (void)testPlaylistPerformsAutomaticRecoveryBeforeSurfaceNetworkError {
  TestPlaylistAudioStreamer *streamer1 = [[TestPlaylistAudioStreamer alloc] init];
  streamer1.autoFailCount = 1;
  streamer1.forcedErrorCode = AS_NETWORK_CONNECTION_FAILED;

  TestPlaylistAudioStreamer *streamer2 = [[TestPlaylistAudioStreamer alloc] init];
  streamer2.autoFailCount = 1;
  streamer2.forcedErrorCode = AS_NETWORK_CONNECTION_FAILED;

  TestPlaylistAudioStreamer *streamer3 = [[TestPlaylistAudioStreamer alloc] init];
  streamer3.autoFailCount = 1;
  streamer3.forcedErrorCode = AS_NETWORK_CONNECTION_FAILED;

  XCTestExpectation *errorExpectation = [self expectationWithDescription:@"error surfaced after auto recovery"];
  errorExpectation.assertForOverFulfill = YES;

  ASPlaylist *playlist = [[ASPlaylist alloc] init];

  __block NSUInteger shortageNotifications = 0;
  id shortageToken = [[NSNotificationCenter defaultCenter]
      addObserverForName:ASNoSongsLeft
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(__unused NSNotification *note) {
                shortageNotifications += 1;
                if (shortageNotifications == 1) {
                  NSURL *url2 = [NSURL URLWithString:@"https://example.com/replacement.mp3"];
                  EnqueueTestStreamer(streamer2);
                  [playlist addSong:url2 play:YES];
                  NSURL *url3 = [NSURL URLWithString:@"https://example.com/fallback.mp3"];
                  EnqueueTestStreamer(streamer3);
                  [playlist addSong:url3 play:NO];
                }
              }];

  __block NSUInteger streamErrorCount = 0;
  id errorToken = [[NSNotificationCenter defaultCenter]
      addObserverForName:ASStreamError
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(__unused NSNotification *note) {
                streamErrorCount += 1;
                [errorExpectation fulfill];
              }];

  EnqueueTestStreamer(streamer1);
  NSURL *url1 = [NSURL URLWithString:@"https://example.com/original.mp3"];
  [playlist addSong:url1 play:YES];

  [self waitForExpectations:@[errorExpectation] timeout:4.0];
  XCTAssertEqual(streamErrorCount, 1u);
  [[NSNotificationCenter defaultCenter] removeObserver:shortageToken];
  [[NSNotificationCenter defaultCenter] removeObserver:errorToken];
  [playlist stop];
}

@end
