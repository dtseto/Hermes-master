#import <XCTest/XCTest.h>
#import "AudioBufferManager.h"

// Mock Delegate
@interface MockAudioBufferManagerDelegate : NSObject <AudioBufferManagerDelegate>
@property (nonatomic, assign) BOOL enqueueCalled;
@property (nonatomic, assign) UInt32 lastEnqueuedIndex;
@property (nonatomic, assign) BOOL suspendCalled;
@property (nonatomic, assign) BOOL resumeCalled;
@property (nonatomic, assign) BOOL startQueueCalled;
@end

@implementation MockAudioBufferManagerDelegate
- (void)audioBufferManager:(AudioBufferManager *)manager copyPacketData:(const void *)inInputData packetSize:(UInt32)inPacketSize toBufferIndex:(UInt32)inBufferIndex offset:(UInt32)inBufferOffset {
    NSLog(@"MockDelegate: copyPacketData called");
}

- (OSStatus)audioBufferManager:(AudioBufferManager *)manager enqueueBufferAtIndex:(UInt32)inBufferIndex bytesFilled:(UInt32)inBytesFilled packetsFilled:(UInt32)inPacketsFilled packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions {
    NSLog(@"MockDelegate: enqueueBufferAtIndex called for index %u", inBufferIndex);
    self.enqueueCalled = YES;
    self.lastEnqueuedIndex = inBufferIndex;
    return noErr;
}

- (void)audioBufferManagerSuspendData:(AudioBufferManager *)manager {
    self.suspendCalled = YES;
}

- (void)audioBufferManagerResumeData:(AudioBufferManager *)manager {
    self.resumeCalled = YES;
}

- (BOOL)audioBufferManagerShouldStartQueue:(AudioBufferManager *)manager {
    return YES;
}

- (void)audioBufferManagerStartQueue:(AudioBufferManager *)manager {
    self.startQueueCalled = YES;
}

@end

@interface AudioBufferManagerTests : XCTestCase
@property (nonatomic, strong) AudioBufferManager *manager;
@property (nonatomic, strong) MockAudioBufferManagerDelegate *delegate;
@end

@implementation AudioBufferManagerTests

- (void)setUp {
    [super setUp];
    self.delegate = [[MockAudioBufferManagerDelegate alloc] init];
    self.manager = [[AudioBufferManager alloc] initWithBufferCount:16
                                                  packetBufferSize:2048
                                                   maxPacketDescs:512
                                                    bufferInfinite:NO
                                                          delegate:self.delegate];
}

- (void)tearDown {
    self.manager = nil;
    self.delegate = nil;
    [super tearDown];
}

- (void)testInitialization {
    XCTAssertNotNil(self.manager);
    XCTAssertFalse([self.manager isWaitingOnBuffer]);
    XCTAssertFalse([self.manager hasQueuedPackets]);
}

- (void)testReset {
    AudioStreamPacketDescription desc = {0};
    desc.mDataByteSize = 100;
    char data[100] = {0};
    [self.manager handlePacketData:data description:desc];
    
    [self.manager reset];
    
    XCTAssertFalse([self.manager isWaitingOnBuffer]);
    XCTAssertFalse([self.manager hasQueuedPackets]);
}

- (void)testHandlePacketData_FillsBuffer {
    AudioStreamPacketDescription desc = {0};
    desc.mDataByteSize = 100;
    char data[100] = {0};
    
    AudioBufferManagerEnqueueResult result = [self.manager handlePacketData:data description:desc];
    
    XCTAssertEqual(result, AudioBufferManagerEnqueueResultCommitted);
    XCTAssertFalse(self.delegate.enqueueCalled);
}

- (void)testHandlePacketData_FlushesWhenFull {
    AudioStreamPacketDescription desc = {0};
    desc.mDataByteSize = 1024; // Half buffer
    char data[1024] = {0};
    
    // First packet
    [self.manager handlePacketData:data description:desc];
    XCTAssertFalse(self.delegate.enqueueCalled);
    
    // Second packet (fills buffer)
    [self.manager handlePacketData:data description:desc];
    
    // Third packet (should trigger flush of first buffer)
    [self.manager handlePacketData:data description:desc];
    
    XCTAssertTrue(self.delegate.enqueueCalled);
    XCTAssertEqual(self.delegate.lastEnqueuedIndex, 0U);
}

- (void)testIncomingPacketsAreCachedWhileBacklogExists {
    AudioStreamPacketDescription desc = {0};
    desc.mDataByteSize = 4;
    char data[4] = {0};

    XCTAssertFalse([self.manager shouldCacheIncomingPackets]);
    [self.manager cachePacketData:data packetSize:sizeof(data) description:desc];
    XCTAssertTrue([self.manager shouldCacheIncomingPackets]);
}

- (void)testIncomingPacketsAreCachedWhileWaitingForInUseBuffer {
    AudioBufferManager *singleBufferManager =
      [[AudioBufferManager alloc] initWithBufferCount:1
                                     packetBufferSize:4
                                      maxPacketDescs:4
                                       bufferInfinite:YES
                                             delegate:self.delegate];
    AudioStreamPacketDescription desc = {0};
    desc.mDataByteSize = 4;
    char data[4] = {0};

    XCTAssertEqual([singleBufferManager handlePacketData:data description:desc],
                   AudioBufferManagerEnqueueResultCommitted);
    desc.mDataByteSize = 1;
    XCTAssertEqual([singleBufferManager handlePacketData:data description:desc],
                   AudioBufferManagerEnqueueResultBlocked);
    XCTAssertTrue([singleBufferManager shouldCacheIncomingPackets]);
}

- (void)testCircularBuffering {
    AudioStreamPacketDescription desc = {0};
    char data[2048] = {0};
    
    // Initial fill for buffer 0
    desc.mDataByteSize = 2048;
    [self.manager handlePacketData:data description:desc];
    
    // We need to flush buffers 0..15
    for (int i = 0; i < 16; i++) {
        // If i > 0, the buffer already has 1 byte from previous flush.
        // So we only need to add 2047 bytes to fill it.
        if (i > 0) {
            desc.mDataByteSize = 2047;
            [self.manager handlePacketData:data description:desc];
        }
        
        // Force flush (add 1 byte)
        // This flushes buffer i, and puts 1 byte into buffer i+1 (or 0 if wrapped)
        desc.mDataByteSize = 1;
        self.delegate.enqueueCalled = NO;
        [self.manager handlePacketData:data description:desc];
        
        XCTAssertTrue(self.delegate.enqueueCalled, @"Buffer %d should have been enqueued", i);
        XCTAssertEqual(self.delegate.lastEnqueuedIndex, (UInt32)i, @"Buffer %d should have index %d", i, i);
        
        // Complete buffer i so it can be reused
        [self.manager bufferCompletedAtIndex:i];
    }
    
    // Now we are at buffer 0 again (wrapped).
    // It currently has 1 byte (from flush of buffer 15).
    
    // Fill the rest (2047 bytes)
    desc.mDataByteSize = 2047;
    [self.manager handlePacketData:data description:desc];
    
    // Flush it by adding 1 byte
    desc.mDataByteSize = 1;
    self.delegate.enqueueCalled = NO;
    [self.manager handlePacketData:data description:desc];
    
    XCTAssertTrue(self.delegate.enqueueCalled, @"Buffer 0 (wrapped) should have been enqueued");
    XCTAssertEqual(self.delegate.lastEnqueuedIndex, 0U, @"Wrapped buffer should have index 0");
}

- (void)testConcurrentPacketHandlingAndBufferCompletion {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Concurrency Test"];
    
    dispatch_queue_t producerQueue = dispatch_queue_create("com.hermes.test.producer", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t consumerQueue = dispatch_queue_create("com.hermes.test.consumer", DISPATCH_QUEUE_SERIAL);
    
    __block BOOL keepRunning = YES;
    NSUInteger packetCount = 1000;
    
    dispatch_async(producerQueue, ^{
        @try {
            AudioStreamPacketDescription desc = {0};
            desc.mDataByteSize = 100;
            char data[100] = {0};
            
            for (NSUInteger i = 0; i < packetCount; i++) {
                [self.manager handlePacketData:data description:desc];
            }
        } @catch (NSException *exception) {
            NSLog(@"Producer exception: %@", exception);
        } @finally {
            keepRunning = NO;
        }
    });
    
    dispatch_async(consumerQueue, ^{
        while (keepRunning) {
            for (int i = 0; i < 16; i++) {
                @try {
                    [self.manager bufferCompletedAtIndex:i];
                } @catch (NSException *exception) {
                    // Ignore assertions for buffers not in use
                }
            }
            usleep(1000); // Sleep 1ms
        }
        [expectation fulfill];
    });
    
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

@end
