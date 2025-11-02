#import "AudioStreamerMetadata.h"

@implementation AudioStreamerMetadata

+ (AudioFileTypeID)hintForFileExtension:(NSString *)extension {
  if ([extension isEqual:@"mp3"]) {
    return kAudioFileMP3Type;
  } else if ([extension isEqual:@"wav"]) {
    return kAudioFileWAVEType;
  } else if ([extension isEqual:@"aifc"]) {
    return kAudioFileAIFCType;
  } else if ([extension isEqual:@"aiff"]) {
    return kAudioFileAIFFType;
  } else if ([extension isEqual:@"mp4"] || [extension isEqual:@"m4a"]) {
    NSLog(@"MP4/M4A detected, using auto-detection");
    return 0;
  } else if ([extension isEqual:@"caf"]) {
    return kAudioFileCAFType;
  } else if ([extension isEqual:@"aac"]) {
    return kAudioFileAAC_ADTSType;
  }
  return 0;
}

+ (AudioFileTypeID)hintForMIMEType:(NSString *)mimeType {
  if ([mimeType isEqual:@"audio/mpeg"]) {
    return kAudioFileMP3Type;
  } else if ([mimeType isEqual:@"audio/x-wav"]) {
    return kAudioFileWAVEType;
  } else if ([mimeType isEqual:@"audio/x-aiff"]) {
    return kAudioFileAIFFType;
  } else if ([mimeType isEqual:@"audio/x-m4a"]) {
    return kAudioFileM4AType;
  } else if ([mimeType isEqual:@"audio/mp4"]) {
    NSLog(@"MP4 MIME detected, using auto-detection");
    return 0;
  } else if ([mimeType isEqual:@"audio/x-caf"]) {
    return kAudioFileCAFType;
  } else if ([mimeType isEqual:@"audio/aac"] ||
             [mimeType isEqual:@"audio/aacp"]) {
    return kAudioFileAAC_ADTSType;
  }
  return 0;
}

+ (BOOL)calculateBitRateWithProcessedPacketSizeTotal:(double)totalPacketSize
                               processedPacketCount:(NSUInteger)packetCount
                                         sampleRate:(double)sampleRate
                                    framesPerPacket:(double)framesPerPacket
                                      minimumPackets:(NSUInteger)minimumPackets
                                             outRate:(double *)outRate {
  if (!outRate) return NO;

  double packetDuration = 0.0;
  if (sampleRate != 0.0) {
    packetDuration = framesPerPacket / sampleRate;
  }

  if (packetDuration && packetCount > minimumPackets) {
    double averagePacketByteSize = totalPacketSize / packetCount;
    *outRate = 8 * averagePacketByteSize / packetDuration;
    return YES;
  }

  return NO;
}

+ (BOOL)calculateDurationWithFileLength:(uint64_t)fileLength
                              dataOffset:(uint64_t)dataOffset
                                 bitRate:(double)bitRate
                              outDuration:(double *)outDuration {
  if (!outDuration) return NO;
  if (bitRate == 0.0 || fileLength == 0) {
    return NO;
  }

  double bytesRemaining = (double)(fileLength - dataOffset);
  *outDuration = bytesRemaining / (bitRate * 0.125);
  return YES;
}

@end
