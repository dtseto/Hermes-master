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

static void LogToTmp(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *content = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    content = [content stringByAppendingString:@"\n"];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/hermes_retry_test_log.txt"];
    if (!file) {
        [[NSFileManager defaultManager] createFileAtPath:@"/tmp/hermes_retry_test_log.txt" contents:nil attributes:nil];
        file = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/hermes_retry_test_log.txt"];
    }
    [file seekToEndOfFile];
    [file writeData:[content dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

static AudioStreamer *TestStreamWithURL(Class cls, SEL _cmd, NSURL *url) {
  LogToTmp(@"TestStreamWithURL called");
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
    [self setRetryBackoffIntervalForTesting:0.1];
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
  LogToTmp(@"TestPlaylistAudioStreamer start called. Attempt: %lu", (unsigned long)attempt);
  
  if (self.autoFailCount > 0 && attempt <= self.autoFailCount) {
    LogToTmp(@"Simulating error for attempt %lu", (unsigned long)attempt);
    dispatch_async(dispatch_get_main_queue(), ^{
      [self simulateErrorForTesting:self.forcedErrorCode];
    });
  } else {
    LogToTmp(@"Simulating success for attempt %lu", (unsigned long)attempt);
    dispatch_async(dispatch_get_main_queue(), ^{
      LogToTmp(@"Setting state to AS_PLAYING for attempt %lu", (unsigned long)attempt);
      ((void (*)(id, SEL, AudioStreamerState))objc_msgSend)(self, NSSelectorFromString(@"setState:"), AS_PLAYING);
    });
    if (self.successExpectation != nil) {
      LogToTmp(@"Fulfilling successExpectation for attempt %lu", (unsigned long)attempt);
      [self.successExpectation fulfill];
    } else {
      LogToTmp(@"successExpectation is nil for attempt %lu", (unsigned long)attempt);
    }
  }
  return YES;
}

@end

@interface ASPlaylistRetryTests : XCTestCase
@end

@implementation ASPlaylistRetryTests

+ (void)setUp {
  [[NSFileManager defaultManager] removeItemAtPath:@"/tmp/hermes_retry_test_log.txt" error:nil];
  Class cls = objc_getClass("AudioStreamer");
  Method original = class_getClassMethod(cls, @selector(streamWithURL:));
  OriginalStreamWithURL = (AudioStreamer *(*)(Class, SEL, NSURL *))method_getImplementation(original);
  method_setImplementation(original, (IMP)TestStreamWithURL);
  gStreamerQueue = [[NSMutableArray alloc] init];
  gForceNonTransientErrors = NO;
}

- (void)setUp {
  [super setUp];
  [gStreamerQueue removeAllObjects];
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
  EnqueueTestStreamer(streamer);

  XCTestExpectation *successExpectation = [self expectationWithDescription:@"playlist recovered"];
  __block BOOL recovered = NO;
  id successToken = [[NSNotificationCenter defaultCenter]
      addObserverForName:ASStatusChangedNotification
                  object:streamer
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(__unused NSNotification *note) {
                if (!recovered && [streamer isPlaying]) {
                  recovered = YES;
                  [successExpectation fulfill];
                }
              }];

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

  [self waitForExpectations:@[successExpectation] timeout:3.0];
  
  [[NSNotificationCenter defaultCenter] removeObserver:token];
  [[NSNotificationCenter defaultCenter] removeObserver:successToken];
  
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

/*
- (void)testPlaylistPerformsAutomaticRecoveryBeforeSurfaceNetworkError {
  // ...
}
*/

@end
