#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "ASPlaylist.h"
#import "AudioStreamer.h"

static AudioStreamer *(*OriginalStreamWithURL)(Class, SEL, NSURL *);
static AudioStreamer *gNextStreamer = nil;

static AudioStreamer *TestStreamWithURL(Class cls, SEL _cmd, NSURL *url) {
  if (gNextStreamer != nil) {
    AudioStreamer *streamer = gNextStreamer;
    gNextStreamer = nil;
    return streamer;
  }
  return OriginalStreamWithURL(cls, _cmd, url);
}

@interface TestPlaylistAudioStreamer : AudioStreamer
@property (nonatomic, assign) NSUInteger startInvocationCount;
@property (nonatomic, assign) NSUInteger autoFailCount;
@property (nonatomic, strong) XCTestExpectation *successExpectation;
@end

@implementation TestPlaylistAudioStreamer

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
    dispatch_async(dispatch_get_main_queue(), ^{
      [self failWithErrorCode:AS_TIMED_OUT];
    });
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
}

+ (void)tearDown {
  Class cls = objc_getClass("AudioStreamer");
  Method original = class_getClassMethod(cls, @selector(streamWithURL:));
  method_setImplementation(original, (IMP)OriginalStreamWithURL);
  OriginalStreamWithURL = NULL;
}

- (void)testPlaylistIgnoresTransientErrorsDuringRetry {
  TestPlaylistAudioStreamer *streamer = [[TestPlaylistAudioStreamer alloc] init];
  streamer.autoFailCount = 1;
  streamer.successExpectation = [self expectationWithDescription:@"playlist recovered"];
  gNextStreamer = streamer;

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

  [self waitForExpectations:@[streamer.successExpectation] timeout:2.0];
  [[NSNotificationCenter defaultCenter] removeObserver:token];
  XCTAssertFalse(streamErrorObserved);
  [playlist stop];
}

- (void)testPlaylistEmitsErrorAfterRetriesExhausted {
  TestPlaylistAudioStreamer *streamer = [[TestPlaylistAudioStreamer alloc] init];
  streamer.autoFailCount = 4; // exceed default retry count
  gNextStreamer = streamer;

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
  [[NSNotificationCenter defaultCenter] removeObserver:token];
  [playlist stop];
}

@end
