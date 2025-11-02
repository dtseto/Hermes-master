#import <XCTest/XCTest.h>

#import "ASPlaylist.h"
#import "AudioStreamer.h"

@interface AudioStreamerDoubleStreamTests : XCTestCase
@end

@implementation AudioStreamerDoubleStreamTests

- (void)testPlaylistRejectsConcurrentStart {
  ASPlaylist *playlist = [[ASPlaylist alloc] init];
  NSURL *url = [NSURL URLWithString:@"https://example.com/fake-stream.mp3"];

  [playlist addSong:url play:NO];
  [playlist addSong:url play:NO];

  dispatch_group_t group = dispatch_group_create();

  dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [playlist play];
  });

  dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [playlist play];
  });

  long waitResult = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)));
  XCTAssertEqual(waitResult, (long)0, @"Concurrent playlist starts should finish without hanging");

  id stream = [playlist valueForKey:@"stream"];
  XCTAssertNotNil(stream, @"Playlist should have an active stream after play");
  NSURL *playingURL = [playlist valueForKey:@"playing"];
  XCTAssertEqualObjects(playingURL, url);
}

- (void)testAudioStreamerIgnoresSecondStartWhilePlaying {
  NSURL *url = [NSURL URLWithString:@"https://example.com/fake-stream.mp3"];
  AudioStreamer *streamer = [AudioStreamer streamWithURL:url];
  XCTAssertNotNil(streamer);

  XCTAssertTrue([streamer start]);

  XCTAssertFalse([streamer start], @"Second start should be ignored while playing");

  [streamer stop];
}

@end
