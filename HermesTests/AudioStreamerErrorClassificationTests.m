#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>

#import "AudioStreamer.h"

@interface AudioStreamer (Testing)
- (void)failWithErrorCode:(AudioStreamerErrorCode)errorCode;
@end

@interface AudioStreamerErrorClassificationTests : XCTestCase
@end

@implementation AudioStreamerErrorClassificationTests

- (void)testTimeoutClassifiedAsTransient {
  BOOL transient = [AudioStreamer isErrorCodeTransient:AS_TIMED_OUT networkError:nil];
  XCTAssertTrue(transient, @"Timeout errors should be treated as transient.");
}

- (void)testDataNotFoundIsNotTransient {
  BOOL transient = [AudioStreamer isErrorCodeTransient:AS_AUDIO_DATA_NOT_FOUND networkError:nil];
  XCTAssertFalse(transient, @"Missing audio data should be treated as fatal.");
}

- (void)testNetworkErrorDomainInfluencesClassification {
  NSError *underlying = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil];
  BOOL transient = [AudioStreamer isErrorCodeTransient:AS_AUDIO_STREAMER_FAILED networkError:underlying];
  XCTAssertTrue(transient, @"NSURLErrorDomain connectivity failures should be transient.");
}

- (void)testErrorNotificationIncludesClassificationMetadata {
  XCTestExpectation *expectation = [self expectationWithDescription:@"classification notification delivered"];

  id token = [[NSNotificationCenter defaultCenter]
      addObserverForName:ASStreamErrorInfoNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *note) {
                NSNumber *code = note.userInfo[ASStreamErrorCodeKey];
                NSNumber *transient = note.userInfo[ASStreamErrorIsTransientKey];
                XCTAssertNotNil(code);
                XCTAssertEqual(code.integerValue, AS_TIMED_OUT);
                XCTAssertEqualObjects(transient, @YES);
                NSError *underlying = note.userInfo[ASStreamErrorUnderlyingErrorKey];
                XCTAssertNotNil(underlying);
                XCTAssertEqualObjects(underlying.domain, NSURLErrorDomain);
                [expectation fulfill];
              }];

  AudioStreamer *streamer = [[AudioStreamer alloc] init];
  NSError *networkErr = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
  [streamer setValue:networkErr forKey:@"networkError"];
  [streamer failWithErrorCode:AS_TIMED_OUT];

  [self waitForExpectations:@[expectation] timeout:1.0];
  [[NSNotificationCenter defaultCenter] removeObserver:token];
}

@end
