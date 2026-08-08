//
//  AudioStreamer+Testing.h
//  Hermes
//
//  Exposes limited testing hooks so unit tests don't need to redeclare
//  private methods via ad-hoc categories.
//

#import "AudioStreamer.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioStreamer (Testing)

/// Returns the queue-buffer capacity selected for a compressed packet size.
+ (UInt32)playbackBufferSizeForMaximumPacketSize:(UInt32)maximumPacketSize
                               minimumBufferSize:(UInt32)minimumBufferSize;

/// Triggers the same failure path the streamer would take when a real error
/// occurs. Only intended for unit tests.
- (void)simulateErrorForTesting:(AudioStreamerErrorCode)code;

/// Starts the buffer health monitor, advances the supplied run loop briefly,
/// and tears the timer back down so tests can exercise the timer lifecycle
/// deterministically. Pass `[NSRunLoop mainRunLoop]` to mirror production.
- (void)runBufferHealthMonitorOnceWithRunLoop:(NSRunLoop *)runLoop;

/// Manually inject audio packets for testing.
- (void)handleAudioPackets:(const void *)inInputData
               numberBytes:(UInt32)inNumberBytes
             numberPackets:(UInt32)inNumberPackets
        packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;

/// Manually trigger property changes for testing.
- (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
                     fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
                                  ioFlags:(UInt32 *)ioFlags;

/// Manually set the sample rate for testing.
- (void)setSampleRateForTesting:(double)sampleRate;

- (void)setDiscontinuousForTesting:(BOOL)flag;
- (void)setParserReadyForPacketsForTesting:(BOOL)flag;
- (void)setFormatSniffBufferForTesting:(NSMutableData * _Nullable)data;
- (void)setAudioQueueForTesting:(AudioQueueRef _Nullable)queue;
- (OSStatus)parseBytes:(const void *)bytes length:(UInt32)length flags:(UInt32)flags;
- (void)setRetryBackoffIntervalForTesting:(NSTimeInterval)interval;
- (void)setInternalStateForTesting:(AudioStreamerState)state;
- (AudioStreamerState)internalStateForTesting;
- (void)setHasAudioQueueStartedForTesting:(BOOL)flag;
- (void)setStateDispatchSynchronousForTesting:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END
