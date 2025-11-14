//
//  AudioStreamerBufferHealthTests.m
//  Hermes
//

#import <XCTest/XCTest.h>
#import "AudioStreamer+Testing.h"

@interface AudioStreamer ()
@property (nonatomic, strong, nullable) NSTimer *bufferHealthTimer;
- (void)checkBufferHealth;
@end

@interface HMSBufferHealthTestStreamer : AudioStreamer
@property (nonatomic, assign) NSUInteger checkBufferHealthCallCount;
@end

@implementation HMSBufferHealthTestStreamer

- (void)checkBufferHealth {
  self.checkBufferHealthCallCount += 1;
  [super checkBufferHealth];
}

@end

@interface AudioStreamerBufferHealthTests : XCTestCase
@end

@implementation AudioStreamerBufferHealthTests

- (void)testBufferHealthMonitorStopsWhenNotPlaying {
  HMSBufferHealthTestStreamer *streamer = [[HMSBufferHealthTestStreamer alloc] init];
  XCTAssertNil(streamer.bufferHealthTimer);

  [streamer runBufferHealthMonitorOnceWithRunLoop:[NSRunLoop mainRunLoop]];

  XCTAssertGreaterThan(streamer.checkBufferHealthCallCount, 0U);
  XCTAssertNil(streamer.bufferHealthTimer);
}

@end
