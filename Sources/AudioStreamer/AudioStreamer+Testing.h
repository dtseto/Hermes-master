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

/// Triggers the same failure path the streamer would take when a real error
/// occurs. Only intended for unit tests.
- (void)simulateErrorForTesting:(AudioStreamerErrorCode)code;

/// Starts the buffer health monitor, advances the supplied run loop briefly,
/// and tears the timer back down so tests can exercise the timer lifecycle
/// deterministically. Pass `[NSRunLoop mainRunLoop]` to mirror production.
- (void)runBufferHealthMonitorOnceWithRunLoop:(NSRunLoop *)runLoop;

@end

NS_ASSUME_NONNULL_END
