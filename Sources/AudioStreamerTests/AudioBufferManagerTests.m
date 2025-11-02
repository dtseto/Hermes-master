#import <XCTest/XCTest.h>
#import "AudioBufferManager.h"

static inline AudioStreamPacketDescription Packet(UInt32 size) {
  AudioStreamPacketDescription desc;
  desc.mStartOffset = 0;
  desc.mVariableFramesInPacket = 0;
  desc.mDataByteSize = size;
  return desc;
}

@interface TestAudioBufferManagerDelegate : NSObject <AudioBufferManagerDelegate>
@property (nonatomic, readonly) NSMutableArray<NSMutableData *> *buffers;
@property (nonatomic, readonly) NSMutableArray<NSDictionary *> *enqueueHistory;
@property (nonatomic) NSUInteger suspendCount;
@property (nonatomic) NSUInteger resumeCount;
@property (nonatomic) BOOL shouldStartQueueResponse;
@property (nonatomic) BOOL queueStarted;
- (instancetype)initWithBufferCount:(UInt32)count packetBufferSize:(UInt32)packetBufferSize;
@end

@implementation TestAudioBufferManagerDelegate

- (instancetype)initWithBufferCount:(UInt32)count packetBufferSize:(UInt32)packetBufferSize {
  if ((self = [super init])) {
    _buffers = [[NSMutableArray alloc] initWithCapacity:count];
    for (UInt32 i = 0; i < count; i++) {
      [_buffers addObject:[NSMutableData dataWithLength:packetBufferSize]];
    }
    _enqueueHistory = [[NSMutableArray alloc] init];
    _shouldStartQueueResponse = NO;
    _queueStarted = NO;
  }
  return self;
}

- (OSStatus)audioBufferManager:(AudioBufferManager *)manager
        enqueueBufferAtIndex:(UInt32)bufferIndex
                 bytesFilled:(UInt32)bytesFilled
               packetsFilled:(UInt32)packetsFilled
          packetDescriptions:(AudioStreamPacketDescription *)packetDescs {
  XCTAssertLessThan(bufferIndex, self.buffers.count);
  NSData *descriptions = [NSData dataWithBytes:packetDescs
                                        length:sizeof(AudioStreamPacketDescription) * packetsFilled];
  NSDictionary *record = @{
    @"index": @(bufferIndex),
    @"bytes": @(bytesFilled),
    @"packets": @(packetsFilled),
    @"descriptions": descriptions ?: [NSData data]
  };
  [self.enqueueHistory addObject:record];
  return noErr;
}

- (void)audioBufferManager:(AudioBufferManager *)manager
             copyPacketData:(const void *)packetData
                 packetSize:(UInt32)packetSize
              toBufferIndex:(UInt32)bufferIndex
                     offset:(UInt32)offset {
  if (packetSize == 0) return;
  XCTAssertLessThan(bufferIndex, self.buffers.count);
  NSMutableData *target = self.buffers[bufferIndex];
  NSRange range = NSMakeRange(offset, packetSize);
  XCTAssertLessThanOrEqual(NSMaxRange(range), target.length);
  [target replaceBytesInRange:range withBytes:packetData];
}

- (void)audioBufferManagerSuspendData:(AudioBufferManager *)manager {
  self.suspendCount += 1;
}

- (void)audioBufferManagerResumeData:(AudioBufferManager *)manager {
  self.resumeCount += 1;
}

- (BOOL)audioBufferManagerShouldStartQueue:(AudioBufferManager *)manager {
  return self.shouldStartQueueResponse;
}

- (void)audioBufferManagerStartQueue:(AudioBufferManager *)manager {
  self.queueStarted = YES;
}

@end

@interface AudioBufferManagerTests : XCTestCase
@end

@implementation AudioBufferManagerTests

- (AudioBufferManager *)makeManagerWithBufferCount:(UInt32)count
                                       packetSize:(UInt32)packetSize
                                   maxPacketDescs:(UInt32)maxPacketDescs
                                   bufferInfinite:(BOOL)bufferInfinite
                                         delegate:(TestAudioBufferManagerDelegate **)outDelegate {
  TestAudioBufferManagerDelegate *delegate =
      [[TestAudioBufferManagerDelegate alloc] initWithBufferCount:count
                                                 packetBufferSize:packetSize];
  AudioBufferManager *manager =
      [[AudioBufferManager alloc] initWithBufferCount:count
                                     packetBufferSize:packetSize
                                      maxPacketDescs:maxPacketDescs
                                       bufferInfinite:bufferInfinite
                                             delegate:delegate];
  XCTAssertNotNil(manager);
  if (outDelegate) {
    *outDelegate = delegate;
  }
  return manager;
}

- (void)testEnqueueingPacketsUpdatesCounters {
  TestAudioBufferManagerDelegate *delegate = nil;
  AudioBufferManager *manager = [self makeManagerWithBufferCount:3
                                                     packetSize:512
                                                 maxPacketDescs:4
                                                 bufferInfinite:NO
                                                       delegate:&delegate];

  const char first[64] = {0};
  const char second[32] = {1};

  AudioBufferManagerEnqueueResult result =
      [manager handlePacketData:first description:Packet(sizeof(first))];
  XCTAssertEqual(result, AudioBufferManagerEnqueueResultCommitted);
  XCTAssertEqual(manager.bytesFilled, (UInt32)sizeof(first));
  XCTAssertEqual(manager.packetsFilled, (UInt32)1);

  result = [manager handlePacketData:second description:Packet(sizeof(second))];
  XCTAssertEqual(result, AudioBufferManagerEnqueueResultCommitted);
  XCTAssertEqual(manager.bytesFilled, (UInt32)(sizeof(first) + sizeof(second)));
  XCTAssertEqual(manager.packetsFilled, (UInt32)2);

  AudioBufferManagerEnqueueResult flush = [manager flushCurrentBuffer];
  XCTAssertEqual(flush, AudioBufferManagerEnqueueResultCommitted);
  XCTAssertEqual(delegate.enqueueHistory.count, (NSUInteger)1);

  NSDictionary *record = delegate.enqueueHistory.firstObject;
  XCTAssertEqualObjects(record[@"index"], @(0));
  XCTAssertEqualObjects(record[@"bytes"], @(sizeof(first) + sizeof(second)));
  XCTAssertEqualObjects(record[@"packets"], @(2));
  XCTAssertEqual(manager.fillBufferIndex, (UInt32)1);
}

- (void)testFillBufferIndexWrapsAfterRoundTrip {
  TestAudioBufferManagerDelegate *delegate = nil;
  AudioBufferManager *manager = [self makeManagerWithBufferCount:2
                                                     packetSize:256
                                                 maxPacketDescs:4
                                                 bufferInfinite:NO
                                                       delegate:&delegate];

  for (NSUInteger cycle = 0; cycle < 4; cycle++) {
    AudioBufferManagerEnqueueResult enqueue =
        [manager handlePacketData:"abc" description:Packet(3)];
    XCTAssertEqual(enqueue, AudioBufferManagerEnqueueResultCommitted);
    XCTAssertEqual([manager flushCurrentBuffer], AudioBufferManagerEnqueueResultCommitted);
    BOOL wasWaiting = [manager bufferCompletedAtIndex:(UInt32)(cycle % 2)];
    XCTAssertFalse(wasWaiting);
  }

  XCTAssertEqual(manager.fillBufferIndex, (UInt32)(4 % 2));
}

- (void)testSuspensionAndResumeWithQueuedPackets {
  TestAudioBufferManagerDelegate *delegate = nil;
  AudioBufferManager *manager = [self makeManagerWithBufferCount:3
                                                     packetSize:128
                                                 maxPacketDescs:4
                                                 bufferInfinite:NO
                                                       delegate:&delegate];

  delegate.shouldStartQueueResponse = NO;

  for (int i = 0; i < 3; i++) {
    AudioBufferManagerEnqueueResult enqueue =
        [manager handlePacketData:"abcd" description:Packet(4)];
    XCTAssertEqual(enqueue, AudioBufferManagerEnqueueResultCommitted);
    AudioBufferManagerEnqueueResult flush = [manager flushCurrentBuffer];
    if (i < 2) {
      XCTAssertEqual(flush, AudioBufferManagerEnqueueResultCommitted);
    } else {
      XCTAssertEqual(flush, AudioBufferManagerEnqueueResultBlocked);
    }
  }

  XCTAssertTrue(manager.isWaitingOnBuffer);
  XCTAssertEqual(delegate.suspendCount, (NSUInteger)1);

  const char cached[8] = {0};
  [manager cachePacketData:cached packetSize:sizeof(cached) description:Packet(sizeof(cached))];

  BOOL waiting = [manager bufferCompletedAtIndex:0];
  XCTAssertTrue(waiting);

  [manager processQueuedPackets];
  XCTAssertFalse(manager.hasQueuedPackets);
  XCTAssertFalse(manager.isWaitingOnBuffer);
  XCTAssertEqual(delegate.resumeCount, (NSUInteger)1);
}

- (void)testZeroLengthPacketIsIgnored {
  TestAudioBufferManagerDelegate *delegate = nil;
  AudioBufferManager *manager = [self makeManagerWithBufferCount:2
                                                     packetSize:128
                                                 maxPacketDescs:4
                                                 bufferInfinite:NO
                                                       delegate:&delegate];

  AudioStreamPacketDescription empty = Packet(0);
  static const char dummy = 0;
  AudioBufferManagerEnqueueResult result = [manager handlePacketData:&dummy description:empty];
  XCTAssertEqual(result, AudioBufferManagerEnqueueResultCommitted);
  XCTAssertEqual(delegate.enqueueHistory.count, (NSUInteger)0);
}

- (void)testOversizedPacketFails {
  TestAudioBufferManagerDelegate *delegate = nil;
  AudioBufferManager *manager = [self makeManagerWithBufferCount:2
                                                     packetSize:64
                                                 maxPacketDescs:4
                                                 bufferInfinite:NO
                                                       delegate:&delegate];

  AudioBufferManagerEnqueueResult result =
      [manager handlePacketData:"0123456789"
                    description:Packet(128)];
  XCTAssertEqual(result, AudioBufferManagerEnqueueResultFailed);
  XCTAssertEqual(delegate.enqueueHistory.count, (NSUInteger)0);
}

- (void)testRepeatedSuspendResumeCycles {
  TestAudioBufferManagerDelegate *delegate = nil;
  AudioBufferManager *manager = [self makeManagerWithBufferCount:2
                                                     packetSize:96
                                                 maxPacketDescs:4
                                                 bufferInfinite:NO
                                                       delegate:&delegate];

  delegate.shouldStartQueueResponse = NO;

  // First cycle: trigger suspend and resume once.
  for (int i = 0; i < 2; i++) {
    (void)[manager handlePacketData:"abcd" description:Packet(4)];
    AudioBufferManagerEnqueueResult flush = [manager flushCurrentBuffer];
    if (i == 1) {
      XCTAssertEqual(flush, AudioBufferManagerEnqueueResultBlocked);
    }
  }
  XCTAssertEqual(delegate.suspendCount, (NSUInteger)1);
  (void)[manager bufferCompletedAtIndex:0];
  [manager processQueuedPackets];
  XCTAssertEqual(delegate.resumeCount, (NSUInteger)1);

  // Second cycle should increment counters again.
  for (int i = 0; i < 2; i++) {
    (void)[manager handlePacketData:"wxyz" description:Packet(4)];
    AudioBufferManagerEnqueueResult flush = [manager flushCurrentBuffer];
    if (i == 1) {
      XCTAssertEqual(flush, AudioBufferManagerEnqueueResultBlocked);
    }
  }
  XCTAssertEqual(delegate.suspendCount, (NSUInteger)2);
  (void)[manager bufferCompletedAtIndex:1];
  [manager processQueuedPackets];
  XCTAssertEqual(delegate.resumeCount, (NSUInteger)2);
}

- (void)testQueueStartDelegation {
  TestAudioBufferManagerDelegate *delegate = nil;
  AudioBufferManager *manager = [self makeManagerWithBufferCount:3
                                                     packetSize:128
                                                 maxPacketDescs:4
                                                 bufferInfinite:NO
                                                       delegate:&delegate];

  delegate.shouldStartQueueResponse = YES;

  (void)[manager handlePacketData:"abcd" description:Packet(4)];
  (void)[manager flushCurrentBuffer];

  XCTAssertTrue(delegate.queueStarted);
}

@end
