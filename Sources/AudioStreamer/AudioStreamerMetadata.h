#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioFile.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Stateless helpers for deriving stream metadata (file type hints, bit rates,
 * durations) that were previously embedded inside AudioStreamer.m.
 *
 * These class methods mirror the original logic so that call sites can
 * delegate without altering behaviour.
 */
@interface AudioStreamerMetadata : NSObject

+ (AudioFileTypeID)hintForFileExtension:(NSString *)extension;

+ (AudioFileTypeID)hintForMIMEType:(NSString *)mimeType;

+ (BOOL)calculateBitRateWithProcessedPacketSizeTotal:(double)totalPacketSize
                               processedPacketCount:(NSUInteger)packetCount
                                         sampleRate:(double)sampleRate
                                    framesPerPacket:(double)framesPerPacket
                                      minimumPackets:(NSUInteger)minimumPackets
                                             outRate:(double *)outRate;

+ (BOOL)calculateDurationWithFileLength:(uint64_t)fileLength
                              dataOffset:(uint64_t)dataOffset
                                 bitRate:(double)bitRate
                              outDuration:(double *)outDuration;

@end

NS_ASSUME_NONNULL_END
