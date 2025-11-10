#import <XCTest/XCTest.h>
#import <objc/message.h>

#import "AudioStreamer.h"
#import "../Sources/AudioStreamer/AudioStreamer+Testing.h"

@interface TestRetryAudioStreamer : AudioStreamer
@property (nonatomic, assign) NSUInteger startInvocationCount;
@property (nonatomic, assign) NSUInteger autoFailCount;
@property (nonatomic, assign) NSTimeInterval simulatedSeekTime;
@property (nonatomic, strong) XCTestExpectation *startExpectation;
@end

@implementation TestRetryAudioStreamer

- (BOOL)openURLSession {
  ((void (*)(id, SEL, AudioStreamerState))objc_msgSend)(self, NSSelectorFromString(@"setState:"), AS_WAITING_FOR_DATA);
  return YES;
}

- (void)teardownAudioResources {
  // Override to avoid touching real CoreAudio resources in tests.
}

- (BOOL)start {
  self.startInvocationCount += 1;
  if (self.startExpectation != nil) {
    [self.startExpectation fulfill];
  }
  NSUInteger attempt = self.startInvocationCount;
  if (self.autoFailCount > 0 && attempt <= self.autoFailCount) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self simulateErrorForTesting:AS_TIMED_OUT];
    });
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      ((void (*)(id, SEL, AudioStreamerState))objc_msgSend)(self, NSSelectorFromString(@"setState:"), AS_PLAYING);
    });
  }
  return YES;
}

@end

@interface AudioStreamerRetryTests : XCTestCase
@end

@implementation AudioStreamerRetryTests

- (void)testTransientErrorSchedulesRetry {
  TestRetryAudioStreamer *streamer = [[TestRetryAudioStreamer alloc] init];
  streamer.startExpectation = [self expectationWithDescription:@"retry start"];
  [streamer setValue:@(AS_PLAYING) forKey:@"state_"];
  [streamer setValue:@(1) forKey:@"maxRetryCount"];
  [streamer setValue:@(0.01) forKey:@"retryBackoffInterval"];

  [streamer simulateErrorForTesting:AS_TIMED_OUT];

  [self waitForExpectations:@[streamer.startExpectation] timeout:1.0];
  XCTAssertEqual(streamer.startInvocationCount, 1U);
}

- (void)testRetryExhaustionTriggersFinalFailure {
  TestRetryAudioStreamer *streamer = [[TestRetryAudioStreamer alloc] init];
  streamer.autoFailCount = 2;
  [streamer setValue:@(AS_PLAYING) forKey:@"state_"];
  [streamer setValue:@(2) forKey:@"maxRetryCount"];
  [streamer setValue:@(0.01) forKey:@"retryBackoffInterval"];

  XCTestExpectation *fatalExpectation = [self expectationWithDescription:@"fatal error delivered"];
  __block NSUInteger notifications = 0;
  id token = [[NSNotificationCenter defaultCenter]
      addObserverForName:ASStreamErrorInfoNotification
                  object:streamer
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *note) {
                BOOL willRetry = [note.userInfo[ASStreamErrorIsTransientKey] boolValue];
                notifications += 1;
                if (notifications < 3) {
                  XCTAssertTrue(willRetry);
                } else {
                  XCTAssertFalse(willRetry);
                  [fatalExpectation fulfill];
                }
              }];

  [streamer simulateErrorForTesting:AS_TIMED_OUT];

  [self waitForExpectations:@[fatalExpectation] timeout:2.0];
  [[NSNotificationCenter defaultCenter] removeObserver:token];
  XCTAssertEqual(streamer.startInvocationCount, 2U);
}

- (void)testStateTransitionsResetRetryBookkeeping {
  TestRetryAudioStreamer *streamer = [[TestRetryAudioStreamer alloc] init];
  [streamer setValue:@3 forKey:@"retryAttemptCount"];
  [streamer setValue:@YES forKey:@"retryScheduled"];
  [streamer setValue:@(12.5) forKey:@"retryResumeTime"];
  [streamer setValue:@(AS_WAITING_FOR_DATA) forKey:@"state_"];

  SEL setStateSEL = NSSelectorFromString(@"setState:");
  ((void (*)(id, SEL, AudioStreamerState))objc_msgSend)(streamer, setStateSEL, AS_PLAYING);

  XCTAssertEqual(streamer.retryAttemptCount, 0U);
  XCTAssertFalse(streamer.retryScheduled);
  XCTAssertEqual(streamer.retryResumeTime, 0.0);

  [streamer setValue:@YES forKey:@"retryScheduled"];
  [streamer setValue:@(8.0) forKey:@"retryResumeTime"];

  ((void (*)(id, SEL, AudioStreamerState))objc_msgSend)(streamer, setStateSEL, AS_STOPPED);

  XCTAssertFalse(streamer.retryScheduled);
  XCTAssertEqual(streamer.retryResumeTime, 0.0);
}

@end
