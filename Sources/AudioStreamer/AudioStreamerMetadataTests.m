#import <XCTest/XCTest.h>
#import <AudioToolbox/AudioFile.h>

#import "AudioStreamerMetadata.h"

@interface AudioStreamerMetadataTests : XCTestCase
@end

@implementation AudioStreamerMetadataTests

- (void)testHintForFileExtensionMatchesOriginalLogic {
  XCTAssertEqual([AudioStreamerMetadata hintForFileExtension:@"mp3"], kAudioFileMP3Type);
  XCTAssertEqual([AudioStreamerMetadata hintForFileExtension:@"wav"], kAudioFileWAVEType);
  XCTAssertEqual([AudioStreamerMetadata hintForFileExtension:@"aac"], kAudioFileAAC_ADTSType);

  XCTAssertEqual([AudioStreamerMetadata hintForFileExtension:@"mp4"], (AudioFileTypeID)0);
  XCTAssertEqual([AudioStreamerMetadata hintForFileExtension:@"unknown"], (AudioFileTypeID)0);
}

- (void)testHintForMIMETypeMatchesOriginalLogic {
  XCTAssertEqual([AudioStreamerMetadata hintForMIMEType:@"audio/mpeg"], kAudioFileMP3Type);
  XCTAssertEqual([AudioStreamerMetadata hintForMIMEType:@"audio/x-wav"], kAudioFileWAVEType);
  XCTAssertEqual([AudioStreamerMetadata hintForMIMEType:@"audio/aacp"], kAudioFileAAC_ADTSType);

  XCTAssertEqual([AudioStreamerMetadata hintForMIMEType:@"audio/mp4"], (AudioFileTypeID)0);
  XCTAssertEqual([AudioStreamerMetadata hintForMIMEType:@"application/octet-stream"], (AudioFileTypeID)0);
}

- (void)testCalculateBitRateSucceedsWhenPacketThresholdMet {
  double outRate = 0.0;
  double sampleRate = 44100.0;
  double framesPerPacket = 1024.0;
  NSUInteger packetCount = 80;
  double totalPacketBytes = 80.0 * 2048.0;

  BOOL success = [AudioStreamerMetadata
                   calculateBitRateWithProcessedPacketSizeTotal:totalPacketBytes
                                           processedPacketCount:packetCount
                                                     sampleRate:sampleRate
                                                framesPerPacket:framesPerPacket
                                                  minimumPackets:50
                                                         outRate:&outRate];
  XCTAssertTrue(success);

  double averagePacketSize = totalPacketBytes / packetCount;
  double packetDuration = framesPerPacket / sampleRate;
  double expectedBitRate = 8.0 * averagePacketSize / packetDuration;
  XCTAssertEqualWithAccuracy(outRate, expectedBitRate, expectedBitRate * 1e-6);
}

- (void)testCalculateBitRateFailsWhenBelowThreshold {
  double outRate = -1.0;
  BOOL success = [AudioStreamerMetadata
                   calculateBitRateWithProcessedPacketSizeTotal:1000.0
                                           processedPacketCount:10
                                                     sampleRate:44100.0
                                                framesPerPacket:1024.0
                                                  minimumPackets:50
                                                         outRate:&outRate];
  XCTAssertFalse(success);
  XCTAssertEqual(outRate, -1.0);
}

- (void)testCalculateDurationMatchesOriginalFormula {
  double bitRate = 192000.0;
  uint64_t fileLength = 1000000;
  uint64_t dataOffset = 10000;
  double duration = 0.0;

  BOOL success = [AudioStreamerMetadata
                   calculateDurationWithFileLength:fileLength
                                             dataOffset:dataOffset
                                                bitRate:bitRate
                                             outDuration:&duration];
  XCTAssertTrue(success);

  double expected = (double)(fileLength - dataOffset) / (bitRate * 0.125);
  XCTAssertEqualWithAccuracy(duration, expected, expected * 1e-6);
}

- (void)testCalculateDurationFailsForZeroBitRateOrLength {
  double duration = 123.0;
  XCTAssertFalse([AudioStreamerMetadata
                   calculateDurationWithFileLength:0
                                             dataOffset:0
                                                bitRate:128000.0
                                             outDuration:&duration]);
  XCTAssertEqual(duration, 123.0);

  XCTAssertFalse([AudioStreamerMetadata
                   calculateDurationWithFileLength:1000
                                             dataOffset:0
                                                bitRate:0.0
                                             outDuration:&duration]);
  XCTAssertEqual(duration, 123.0);
}

@end
