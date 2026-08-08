#import <XCTest/XCTest.h>
#import "AudioStreamer.h"
#import "AudioStreamer+Testing.h"
#import "AudioBufferManager.h"

// Expose that AudioStreamer implements the delegate methods
@interface AudioStreamer (AudioBufferManagerDelegate) <AudioBufferManagerDelegate>
- (void)createQueue;
- (void)teardownAudioResources;
@end

// Declare conformance to AudioBufferManagerDelegate
@interface TestAudioStreamer : AudioStreamer <AudioBufferManagerDelegate>
@property (nonatomic, assign) BOOL queueCreated;
@property (nonatomic, assign) BOOL queueStarted;
@property (nonatomic, assign) BOOL simulateParseFailure;
@end

@implementation TestAudioStreamer

- (OSStatus)parseBytes:(const void *)bytes length:(UInt32)length flags:(UInt32)flags {
    if (self.simulateParseFailure) {
        return kAudioFileStreamError_UnsupportedFileType; // Or any error
    }
    return [super parseBytes:bytes length:length flags:flags];
}

// ...

// ...

- (void)createQueue {
// ... (existing code)
    if (self.queueCreated) return;
    
    // Manually initialize bufferManager to avoid AudioQueue dependency
    AudioBufferManager *mgr = [[AudioBufferManager alloc] initWithBufferCount:16
                                                             packetBufferSize:8192
                                                              maxPacketDescs:512
                                                              bufferInfinite:NO
                                                                    delegate:self];
    [self setValue:mgr forKey:@"bufferManager"];
    
    // Set packetBufferSize
    [self setValue:@(8192) forKey:@"packetBufferSize"];
    
    // Set dummy audioQueue to pass NULL check
    [self setAudioQueueForTesting:(AudioQueueRef)1];
    
    self.queueCreated = YES;
}

- (BOOL)openURLSession {
    [self setValue:@(AS_WAITING_FOR_DATA) forKey:@"state_"];
    return YES;
}

- (void)audioBufferManagerStartQueue:(AudioBufferManager *)manager {
    self.queueStarted = YES;
    // Use KVC to set private state
    [self setValue:@(AS_PLAYING) forKey:@"state_"];
}

- (OSStatus)audioBufferManager:(AudioBufferManager *)manager
          enqueueBufferAtIndex:(UInt32)index
                   bytesFilled:(UInt32)bytesFilled
                 packetsFilled:(UInt32)packetsFilled
            packetDescriptions:(AudioStreamPacketDescription *)packetDescs {
    return noErr;
}

// Implement other required delegate methods to avoid warnings/crashes
- (void)audioBufferManager:(AudioBufferManager *)manager copyPacketData:(const void *)inInputData packetSize:(UInt32)inPacketSize toBufferIndex:(UInt32)inBufferIndex offset:(UInt32)inBufferOffset {
    // No-op
}

- (void)audioBufferManagerSuspendData:(AudioBufferManager *)manager {
    // No-op
}

- (void)audioBufferManagerResumeData:(AudioBufferManager *)manager {
    // No-op
}

- (void)teardownAudioResources {
    // Prevent crash by setting audioQueue to NULL before super tries to dispose it
    [self setAudioQueueForTesting:(AudioQueueRef)NULL];
    [super teardownAudioResources];
}

@end

@interface AudioStreamerTests : XCTestCase
@property (nonatomic, strong) TestAudioStreamer *streamer;
@end

@implementation AudioStreamerTests

- (void)testPlaybackBufferSizePreservesConfiguredReserve {
  XCTAssertEqual([AudioStreamer playbackBufferSizeForMaximumPacketSize:1024
                                                     minimumBufferSize:8192],
                 8192U);
}

- (void)testPlaybackBufferSizeStillFitsOversizedPacket {
  XCTAssertEqual([AudioStreamer playbackBufferSizeForMaximumPacketSize:12288
                                                     minimumBufferSize:8192],
                 12288U);
}

- (void)setUp {
    [super setUp];
    // Use streamWithURL instead of initWithURL
    self.streamer = (TestAudioStreamer *)[TestAudioStreamer streamWithURL:[NSURL URLWithString:@"http://example.com/stream.mp3"]];
}

- (void)tearDown {
    [self.streamer stop];
    self.streamer = nil;
    [super tearDown];
}

- (void)testStartupBuffering {
    [self.streamer start];
    
    // Initial state
    XCTAssertTrue([self.streamer isWaiting], @"Should be waiting for data");
    
    // Simulate ReadyToProducePackets
    [self.streamer setDiscontinuousForTesting:YES];
    [self.streamer setParserReadyForPacketsForTesting:YES];
    [self.streamer setFormatSniffBufferForTesting:nil];
    // kStartupBufferSeconds is 5.0.
    // Let's assume 44.1kHz, 16-bit stereo (4 bytes per frame).
    // 1 second = 44100 frames = 176400 bytes.
    // We need > 5 seconds.
    
    AudioStreamPacketDescription desc = {0};
    desc.mDataByteSize = 100;
    desc.mVariableFramesInPacket = 1; 
    
    // Set sampleRate via testing hook
    [self.streamer setSampleRateForTesting:44100.0];
    
    char data[100] = {0};
    
    // Inject 4 seconds of audio
    // 4 seconds * 44100 frames/sec = 176400 frames.
    // If each packet is 1000 frames.
    desc.mVariableFramesInPacket = 1000;
    int packetsFor4Seconds = (4 * 44100) / 1000; // 176 packets
    
    for (int i = 0; i < packetsFor4Seconds; i++) {
        // Prevent timeout
        [self.streamer setValue:@(1) forKey:@"events"];
        
        [self.streamer handleAudioPackets:data
                              numberBytes:100
                            numberPackets:1
                       packetDescriptions:&desc];
    }
    
    // Should still be waiting for data (buffering)
    XCTAssertTrue([self.streamer isWaiting], @"Should still be waiting after 4 seconds buffered");
    XCTAssertFalse(self.streamer.queueStarted);
    
    // Inject 2 more seconds (total 6)
    int packetsFor2Seconds = (2 * 44100) / 1000; // 88 packets
    
    for (int i = 0; i < packetsFor2Seconds; i++) {
        // Prevent timeout
        [self.streamer setValue:@(1) forKey:@"events"];
        
        [self.streamer handleAudioPackets:data
                              numberBytes:100
                            numberPackets:1
                       packetDescriptions:&desc];
    }
    
    // Should be playing now
    XCTAssertTrue([self.streamer isPlaying], @"Should be playing after 6 seconds buffered");
    XCTAssertTrue(self.streamer.queueStarted);
}

- (void)testADTSFallback {
    [self.streamer start];
    
    // Set simulate failure
    self.streamer.simulateParseFailure = YES;
    
    // Simulate response to initialize audioFileStream
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://example.com/stream.mp3"]
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": @"audio/mpeg"}];
    
    [self.streamer URLSession:(NSURLSession *)[NSNull null] dataTask:(NSURLSessionDataTask *)[NSNull null] didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition disposition) {
        // No-op
    }];
    
    // Inject some data via didReceiveData
    char bytes[100] = {0};
    NSData *data = [NSData dataWithBytes:bytes length:100];
    
    [self.streamer URLSession:(NSURLSession *)[NSNull null] dataTask:(NSURLSessionDataTask *)[NSNull null] didReceiveData:data];
    
    // Verify fallback attempted
    BOOL fallback = [[self.streamer valueForKey:@"adtsFallbackAttempted"] boolValue];
    XCTAssertTrue(fallback, @"Should have attempted ADTS fallback");
    
    // Verify file type hint changed to AAC_ADTS
    AudioFileTypeID hint = [[self.streamer valueForKey:@"currentFileTypeHint"] unsignedIntValue];
    XCTAssertEqual(hint, kAudioFileAAC_ADTSType, @"Should have switched to ADTS hint");
}

- (void)testErrorHandling {
    self.streamer.maxRetryCount = 0; // Disable retries to force stop
    [self.streamer start];
    
    // Expect state change to STOPPED
    [self expectationForNotification:@"ASStatusChangedNotification"
                              object:self.streamer
                             handler:^BOOL(NSNotification *notification) {
        AudioStreamerState state = [[self.streamer valueForKey:@"state_"] intValue];
        return state == AS_STOPPED;
    }];
    
    // Simulate network error
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    
    [self.streamer URLSession:(NSURLSession *)[NSNull null] task:(NSURLSessionTask *)[NSNull null] didCompleteWithError:error];
    
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    
    // Verify error code
    AudioStreamerErrorCode code = [[self.streamer valueForKey:@"errorCode"] intValue];
    XCTAssertEqual(code, AS_NETWORK_CONNECTION_FAILED, @"Error code should be AS_NETWORK_CONNECTION_FAILED");
}

@end
