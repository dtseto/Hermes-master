//
//  AudioStreamer.m
//  StreamingAudioPlayer
//
//  Created by Matt Gallagher on 27/09/08.
//  Copyright 2008 Matt Gallagher. All rights reserved.
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//

/* This file has been heavily modified since its original distribution bytes
   Alex Crichton for the Hermes project */

#import "AudioStreamer.h"
#import "AudioBufferManager.h"
#import "AudioStreamerMetadata.h"
#import "AudioStreamerStateController.h"
#include <errno.h>

#define BitRateEstimationMinPackets 50

#define PROXY_SYSTEM 0
#define PROXY_SOCKS  1
#define PROXY_HTTP   2

/* Default number and size of audio queue buffers */
#define kDefaultNumAQBufs 16
#define kDefaultAQDefaultBufSize 2048
#define HMS_MAX_TRANSIENT_RETRIES_DEFAULT 5
#define HMS_RETRY_BACKOFF_DEFAULT 1.0
#define HMS_RETRY_BACKOFF_MAX 5.0
#define kMaxFormatSniffBytes (256 * 1024)
#define kStartupBufferSeconds 5.0
#define kStartupBufferMinimumBuffers 6
#define kContentLengthToleranceFraction 0.02
#define kContentLengthToleranceMinimum (32 * 1024)

#define CHECK_ERR(err, code) {                                                 \
    if (err) { [self failWithErrorCode:code]; return; }                        \
  }

#if defined(DEBUG) && 0
#define LOG(fmt, args...) NSLog(@"%s " fmt, __PRETTY_FUNCTION__, ##args)
#else
#define LOG(...)
#endif

NSString * const ASBitrateReadyNotification = @"ASBitrateReadyNotification";
NSString * const ASStatusChangedNotification = @"ASStatusChangedNotification";
NSString * const ASDidChangeStateDistributedNotification = @"hermes.state";
NSString * const ASStreamErrorInfoNotification = @"ASStreamErrorInfoNotification";
NSString * const ASStreamErrorCodeKey = @"code";
NSString * const ASStreamErrorIsTransientKey = @"transient";
NSString * const ASStreamErrorUnderlyingErrorKey = @"underlyingError";

@interface AudioStreamer () <AudioBufferManagerDelegate>
@property (nonatomic, strong) NSLock *stateLock;
@property (nonatomic, assign) BOOL isStateChanging;
@property (nonatomic, assign) NSTimeInterval lastPlayCall;
@property (nonatomic, assign) NSTimeInterval lastPauseCall;
@property (nonatomic, strong) AudioStreamerStateController * _Nonnull stateController;
@property (nonatomic, readwrite) NSUInteger retryAttemptCount;
@property (nonatomic, assign) NSUInteger retryGeneration;
@property (nonatomic, assign) NSTimeInterval retryBackoffInterval;
@property (nonatomic, readwrite) BOOL retryScheduled;
@property (nonatomic, readwrite) double retryResumeTime;
@property (nonatomic, assign) AudioFileTypeID currentFileTypeHint;
@property (nonatomic, assign) BOOL parserReadyForPackets;
@property (nonatomic, strong, nullable) NSMutableData *formatSniffBuffer;
@property (nonatomic, assign) BOOL adtsFallbackAttempted;
@property (nonatomic, assign) int64_t expectedContentLength;
@property (nonatomic, assign) uint64_t totalBytesReceived;
@property (nonatomic, assign) double startupBufferedDuration;
@property (nonatomic, assign) BOOL startupBufferSatisfied;
@property (nonatomic, assign) BOOL hasAudioQueueStarted;
@property (nonatomic, strong, nullable) NSTimer *bufferHealthTimer;
@property (nonatomic, assign) NSTimeInterval playbackStartTimestamp;

- (void)handleFailureSynchronouslyWithCode:(AudioStreamerErrorCode)anErrorCode;
- (void)prepareForRetry;
- (void)scheduleRetryForError:(AudioStreamerErrorCode)errorCode;
- (void)teardownAudioResources;
- (void)applyRetrySideEffectsForState:(AudioStreamerState)newState;
- (OSStatus)openAudioFileStreamWithHint:(AudioFileTypeID)hint;
- (BOOL)attemptADTSFallbackReplayingBufferedDataWithBytes:(const void *)bytes
                                                   length:(UInt32)length
                                                    error:(OSStatus)error;
- (void)startBufferHealthMonitor;
- (void)stopBufferHealthMonitor;
- (void)checkBufferHealth;
- (void)installBufferHealthTimerIfNeeded;
- (void)invalidateBufferHealthTimer;

- (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
                     fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
                                  ioFlags:(UInt32 *)ioFlags;
- (void)handleAudioPackets:(const void *)inInputData
               numberBytes:(UInt32)inNumberBytes
             numberPackets:(UInt32)inNumberPackets
        packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;
- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer;
- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID;

@end

/* Implementation */
@implementation AudioStreamer

@synthesize errorCode;
@synthesize networkError;
@synthesize httpHeaders;
@synthesize url;
@synthesize fileType;
@synthesize bufferCnt;
@synthesize bufferSize;
@synthesize bufferInfinite;
@synthesize timeoutInterval;

/* AudioFileStream callback when properties are available */
static void MyPropertyListenerProc(void *inClientData,
                            AudioFileStreamID inAudioFileStream,
                            AudioFileStreamPropertyID inPropertyID,
                            UInt32 *ioFlags) {
  AudioStreamer* streamer = (__bridge AudioStreamer *)inClientData;
  [streamer handlePropertyChangeForFileStream:inAudioFileStream
                         fileStreamPropertyID:inPropertyID
                                      ioFlags:ioFlags];
}

/* AudioFileStream callback when packets are available */
static void MyPacketsProc(void *inClientData, UInt32 inNumberBytes, UInt32
                   inNumberPackets, const void *inInputData,
                   AudioStreamPacketDescription  *inPacketDescriptions) {
  AudioStreamer* streamer = (__bridge AudioStreamer *)inClientData;
  [streamer handleAudioPackets:inInputData
                   numberBytes:inNumberBytes
                 numberPackets:inNumberPackets
            packetDescriptions:inPacketDescriptions];
}

/* AudioQueue callback notifying that a buffer is done */
static void MyAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer) {
  AudioStreamer* streamer = (__bridge AudioStreamer*)inClientData;
  [streamer handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

/* AudioQueue callback that a property has changed */
static void MyAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ,
                                   AudioQueuePropertyID inID) {
  AudioStreamer* streamer = (__bridge AudioStreamer *)inUserData;
  [streamer handlePropertyChangeForQueue:inAQ propertyID:inID];
}

+ (AudioStreamer*) streamWithURL:(NSURL*)url {
    assert(url != nil);
    AudioStreamer *stream = [[AudioStreamer alloc] init];
    stream->url = url;
    stream->bufferCnt  = kDefaultNumAQBufs;
    stream->bufferSize = kDefaultAQDefaultBufSize;
    stream->timeoutInterval = 10;
    
    // Apply optimizations for macOS 15
    [stream setupOptimizedSettings];
    
    return stream;
}

- (id)init {
    if (self = [super init]) {
        self.stateLock = [[NSLock alloc] init];
        self.isStateChanging = NO;
        self.lastPlayCall = 0;
        self.lastPauseCall = 0;
        state_ = AS_INITIALIZED;
        _stateController = [[AudioStreamerStateController alloc]
                             initWithOwner:self
                             statePointer:&state_
                             notificationCenter:[NSNotificationCenter defaultCenter]
                             distributedNotificationCenter:[NSDistributedNotificationCenter defaultCenter]
                             targetQueue:dispatch_get_main_queue()];
        _maxRetryCount = HMS_MAX_TRANSIENT_RETRIES_DEFAULT;
        _retryBackoffInterval = HMS_RETRY_BACKOFF_DEFAULT;
        _retryAttemptCount = 0;
        _retryGeneration = 0;
        _retryScheduled = NO;
        _retryResumeTime = 0.0;
        _currentFileTypeHint = 0;
        _parserReadyForPackets = NO;
        _adtsFallbackAttempted = NO;
        _expectedContentLength = -1;
        _totalBytesReceived = 0;
        _startupBufferedDuration = 0.0;
        _startupBufferSatisfied = NO;
        _hasAudioQueueStarted = NO;
        _playbackStartTimestamp = 0.0;
    }
    return self;
}

- (void)dealloc {
  [self stop];
  assert(timeout == nil);
  assert(buffers == NULL);
  assert(bufferManager == nil);
}

- (void)setupOptimizedSettings {
    // Simple optimization for modern Macs
    NSLog(@"Setting up optimized audio settings for macOS 15+");
    
    // Increase buffer settings for better performance on modern hardware
    if (bufferCnt < 20) {
        bufferCnt = 20;  // Increase from default 16
        NSLog(@"Increased buffer count to %u for better performance", bufferCnt);
    }
    
    if (bufferSize < 4096) {
        bufferSize = 4096;  // Increase from default 2048
        NSLog(@"Increased buffer size to %u for better performance", bufferSize);
    }
}

- (void) setHTTPProxy:(NSString*)host port:(int)port {
  proxyHost = host;
  proxyPort = port;
  proxyType = PROXY_HTTP;
}

- (void) setSOCKSProxy:(NSString*)host port:(int)port {
  proxyHost = host;
  proxyPort = port;
  proxyType = PROXY_SOCKS;
}

- (void)setBufferInfinite:(BOOL)newBufferInfinite {
  bufferInfinite = newBufferInfinite;
  if (bufferManager != nil) {
    [bufferManager updateBufferInfinite:newBufferInfinite];
  }
}

- (BOOL)setVolume: (double) volume {
  if (audioQueue != NULL) {
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, volume);
    return YES;
  }
  return NO;
}

+ (NSString *)stringForErrorCode:(AudioStreamerErrorCode)anErrorCode {
  switch (anErrorCode) {
    case AS_NO_ERROR:
      return @"No error.";
    case AS_FILE_STREAM_GET_PROPERTY_FAILED:
      return @"File stream get property failed";
    case AS_FILE_STREAM_SET_PROPERTY_FAILED:
      return @"File stream set property failed";
    case AS_FILE_STREAM_SEEK_FAILED:
      return @"File stream seek failed";
    case AS_FILE_STREAM_PARSE_BYTES_FAILED:
      return @"Parse bytes failed";
    case AS_AUDIO_QUEUE_CREATION_FAILED:
      return @"Audio queue creation failed";
    case AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED:
      return @"Audio queue buffer allocation failed";
    case AS_AUDIO_QUEUE_ENQUEUE_FAILED:
      return @"Queueing of audio buffer failed";
    case AS_AUDIO_QUEUE_ADD_LISTENER_FAILED:
      return @"Failed to add listener to audio queue";
    case AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED:
      return @"Failed to remove listener from audio queue";
    case AS_AUDIO_QUEUE_START_FAILED:
      return @"Failed to start the audio queue";
    case AS_AUDIO_QUEUE_BUFFER_MISMATCH:
      return @"Audio queue buffer mismatch";
    case AS_FILE_STREAM_OPEN_FAILED:
      return @"Failed to open file stream";
    case AS_FILE_STREAM_CLOSE_FAILED:
      return @"Failed to close the file stream";
    case AS_AUDIO_QUEUE_DISPOSE_FAILED:
      return @"Couldn't dispose of audio queue";
    case AS_AUDIO_QUEUE_PAUSE_FAILED:
      return @"Failed to pause the audio queue";
    case AS_AUDIO_QUEUE_FLUSH_FAILED:
      return @"Failed to flush the audio queue";
    case AS_AUDIO_DATA_NOT_FOUND:
      return @"No audio data found";
    case AS_GET_AUDIO_TIME_FAILED:
      return @"Couldn't get audio time";
    case AS_NETWORK_CONNECTION_FAILED:
      return @"Network connection failure";
    case AS_AUDIO_QUEUE_STOP_FAILED:
      return @"Audio queue stop failed";
    case AS_AUDIO_STREAMER_FAILED:
      return @"Audio streamer failed";
    case AS_AUDIO_BUFFER_TOO_SMALL:
      return @"Audio buffer too small";
    case AS_TIMED_OUT:
      return @"Timed out";
    default:
      break;
  }

  return @"Audio streaming failed";
}

+ (BOOL)isErrorCodeTransient:(AudioStreamerErrorCode)errorCode
                networkError:(NSError *)networkError {
  switch (errorCode) {
    case AS_TIMED_OUT:
    case AS_NETWORK_CONNECTION_FAILED:
    case AS_AUDIO_QUEUE_START_FAILED:
    case AS_AUDIO_QUEUE_ENQUEUE_FAILED:
    case AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED:
    case AS_AUDIO_QUEUE_CREATION_FAILED:
    case AS_AUDIO_QUEUE_ADD_LISTENER_FAILED:
    case AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED:
    case AS_AUDIO_QUEUE_BUFFER_MISMATCH:
    case AS_AUDIO_QUEUE_DISPOSE_FAILED:
    case AS_AUDIO_QUEUE_STOP_FAILED:
    case AS_AUDIO_QUEUE_FLUSH_FAILED:
    case AS_AUDIO_STREAMER_FAILED:
      return YES;
    default:
      break;
  }

  if (networkError != nil) {
    NSString *domain = networkError.domain;
    if ([domain isEqualToString:NSURLErrorDomain]) {
      switch (networkError.code) {
        case NSURLErrorTimedOut:
        case NSURLErrorCannotFindHost:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorNetworkConnectionLost:
        case NSURLErrorDNSLookupFailed:
        case NSURLErrorNotConnectedToInternet:
          return YES;
        default:
          break;
      }
    } else if ([domain isEqualToString:NSPOSIXErrorDomain]) {
      switch (networkError.code) {
        case ETIMEDOUT:
        case ECONNRESET:
        case ECONNABORTED:
        case ENETDOWN:
        case ENETUNREACH:
          return YES;
        default:
          break;
      }
    }
  }

  return NO;
}

- (BOOL)isPlaying {
  return state_ == AS_PLAYING;
}

- (BOOL)isPaused {
  return state_ == AS_PAUSED;
}

- (BOOL)isWaiting {
  return state_ == AS_WAITING_FOR_DATA ||
         state_ == AS_WAITING_FOR_QUEUE_TO_START;
}

- (BOOL)isDone {
  return state_ == AS_DONE || state_ == AS_STOPPED;
}

- (AudioStreamerDoneReason)doneReason {
  if (errorCode) {
    return AS_DONE_ERROR;
  }
  switch (state_) {
    case AS_STOPPED:
      return AS_DONE_STOPPED;
    case AS_DONE:
      return AS_DONE_EOF;
    default:
      break;
  }
  return AS_NOT_DONE;
}

- (BOOL)start {
  NSLog(@"AudioStreamer attempting to start");

  // Check if already has active session
  if (session != NULL) {
    NSLog(@"AudioStreamer already has active session - returning NO");
    return NO;
  }
  
  // Check if audio queue already exists
  if (audioQueue != NULL) {
    NSLog(@"AudioStreamer already has audio queue - returning NO");
    return NO;
  }
  
  // Check if in correct state
  if (state_ != AS_INITIALIZED) {
    NSLog(@"AudioStreamer not in initialized state (current: %d) - returning NO", state_);
    return NO;
  }

  self.expectedContentLength = -1;
  self.totalBytesReceived = 0;
  self.startupBufferedDuration = 0.0;
  self.startupBufferSatisfied = NO;
  self.hasAudioQueueStarted = NO;

  AudioStreamerStateController *controller = self.stateController;
  if (controller) {
    [controller disableStopEnforcement];
  }
  
  // Check if timeout already exists
  if (timeout != nil) {
    NSLog(@"AudioStreamer timeout already exists - returning NO");
    return NO;
  }
  
  // Try to open URL session
  if (![self openURLSession]) {
    NSLog(@"AudioStreamer failed to open URL session - returning NO");
    return NO;
  }
  
  // Create timeout timer
  timeout = [NSTimer scheduledTimerWithTimeInterval:timeoutInterval
                                             target:self
                                           selector:@selector(checkTimeout)
                                           userInfo:nil
                                            repeats:YES];
  
  NSLog(@"AudioStreamer started successfully");
  return YES;
}

- (void)teardownAudioResources {
  [timeout invalidate];
  timeout = nil;

  [self closeURLSession];
  if (audioFileStream) {
    err = AudioFileStreamClose(audioFileStream);
    assert(!err);
    audioFileStream = nil;
    self.formatSniffBuffer = nil;
    self.parserReadyForPackets = NO;
    self.adtsFallbackAttempted = NO;
    self.currentFileTypeHint = 0;
    self.startupBufferedDuration = 0.0;
    self.startupBufferSatisfied = NO;
  }
  if (audioQueue) {
    AudioQueueStop(audioQueue, true);
    err = AudioQueueDispose(audioQueue, true);
    assert(!err);
    audioQueue = nil;
    self.hasAudioQueueStarted = NO;
  }
  [self stopBufferHealthMonitor];
  if (buffers != NULL) {
    free(buffers);
    buffers = NULL;
  }
  if (bufferManager != nil) {
    [bufferManager reset];
    bufferManager = nil;
  }

  httpHeaders = nil;
  seekByteOffset = 0;
  packetBufferSize = 0;
  processedPacketsCount = 0;
  processedPacketsSizeTotal = 0;
}

- (BOOL)pause {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    // Prevent rapid double-calls (within 100ms)
    if (now - self.lastPauseCall < 0.1) {
        NSLog(@"WARNING: Double pause call detected! Ignoring.");
        return NO;
    }
    self.lastPauseCall = now;
    
    [self.stateLock lock];
    
    if (state_ != AS_PLAYING) {
        NSLog(@"Pause called but state is not playing: %d", state_);
        [self.stateLock unlock];
        return NO;
    }
    
    if (!audioQueue) {
        NSLog(@"Pause called but audioQueue is NULL");
        [self.stateLock unlock];
        return NO;
    }
    
    [self.stateLock unlock];
    
    OSStatus err = AudioQueuePause(audioQueue);
    if (err) {
        NSLog(@"AudioQueuePause failed with error: %d", (int)err);
        [self failWithErrorCode:AS_AUDIO_QUEUE_PAUSE_FAILED];
        return NO;
    }
    
    [self setState:AS_PAUSED];
    return YES;
}

- (BOOL)play {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    // Prevent rapid double-calls (within 100ms)
    if (now - self.lastPlayCall < 0.1) {
        NSLog(@"WARNING: Double play call detected! Ignoring.");
        return NO;
    }
    self.lastPlayCall = now;
    
    [self.stateLock lock];
    
    if (state_ != AS_PAUSED) {
        NSLog(@"Play called but state is not paused: %d", state_);
        [self.stateLock unlock];
        return NO;
    }
    
    if (!audioQueue) {
        NSLog(@"Play called but audioQueue is NULL");
        [self.stateLock unlock];
        return NO;
    }
    
    [self.stateLock unlock];
    
    OSStatus err = AudioQueueStart(audioQueue, NULL);
    if (err) {
        NSLog(@"AudioQueueStart failed with error: %d", (int)err);
        [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
        return NO;
    }
    
    [self setState:AS_PLAYING];
    return YES;
}

- (void)stop {
  if (![self isDone]) {
    [self setState:AS_STOPPED];
  }
  self.retryGeneration += 1;
  self.retryScheduled = NO;
  self.retryAttemptCount = 0;
  self.retryResumeTime = 0.0;
  [self teardownAudioResources];
}

- (BOOL)seekToTime:(double)newSeekTime {
  double bitrate;
  double duration;
  if (![self calculatedBitRate:&bitrate]) return NO;
  if (![self duration:&duration]) return NO;
  if (bitrate == 0.0 || fileLength <= 0) {
    return NO;
  }
  assert(!seeking);
  seeking = YES;

  //
  // Calculate the byte offset for seeking
  //
  seekByteOffset = dataOffset +
    (newSeekTime / duration) * (fileLength - dataOffset);

  //
  // Attempt to leave 1 useful packet at the end of the file (although in
  // reality, this may still seek too far if the file has a long trailer).
  //
  if (seekByteOffset > fileLength - 2 * packetBufferSize) {
    seekByteOffset = fileLength - 2 * packetBufferSize;
  }

  //
  // Store the old time from the audio queue and the time that we're seeking
  // to so that we'll know the correct time progress after seeking.
  //
  seekTime = newSeekTime;

  //
  // Attempt to align the seek with a packet boundary
  //
  double packetDuration = asbd.mFramesPerPacket / asbd.mSampleRate;
  if (packetDuration > 0 && bitrate > 0) {
    UInt32 ioFlags = 0;
    SInt64 packetAlignedByteOffset;
    SInt64 seekPacket = floor(newSeekTime / packetDuration);
    err = AudioFileStreamSeek(audioFileStream, seekPacket,
                              &packetAlignedByteOffset, &ioFlags);
    if (!err && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated)) {
      seekTime -= ((seekByteOffset - dataOffset) - packetAlignedByteOffset) * 8.0 / bitrate;
      seekByteOffset = packetAlignedByteOffset + dataOffset;
    }
  }

  [self closeURLSession];

  /* Stop audio for now */
  err = AudioQueueStop(audioQueue, true);
  if (err) {
    seeking = NO;
    [self failWithErrorCode:AS_AUDIO_QUEUE_STOP_FAILED];
    return NO;
  }

  /* Open a new session with a new offset */
  BOOL ret = [self openURLSession];
  seeking = NO;
  return ret;
}

- (BOOL) progress:(double*)ret {
  double sampleRate = asbd.mSampleRate;
  if (state_ == AS_STOPPED) {
    *ret = lastProgress;
    return YES;
  }
  if (sampleRate <= 0 || (state_ != AS_PLAYING && state_ != AS_PAUSED))
    return NO;

  AudioTimeStamp queueTime;
  Boolean discontinuity;
  err = AudioQueueGetCurrentTime(audioQueue, NULL, &queueTime, &discontinuity);
  if (err) {
    return NO;
  }

  double progress = seekTime + queueTime.mSampleTime / sampleRate;
  if (progress < 0.0) {
    progress = 0.0;
  }

  lastProgress = progress;
  *ret = progress;
  return YES;
}

- (BOOL) calculatedBitRate:(double*)rate {
  return [AudioStreamerMetadata
            calculateBitRateWithProcessedPacketSizeTotal:processedPacketsSizeTotal
                                    processedPacketCount:processedPacketsCount
                                              sampleRate:asbd.mSampleRate
                                         framesPerPacket:asbd.mFramesPerPacket
                                           minimumPackets:BitRateEstimationMinPackets
                                                  outRate:rate];
}

- (BOOL) duration:(double*)ret {
  double calculatedBitRate;
  if (![self calculatedBitRate:&calculatedBitRate]) return NO;
  return [AudioStreamerMetadata
           calculateDurationWithFileLength:fileLength
                                  dataOffset:dataOffset
                                     bitRate:calculatedBitRate
                                  outDuration:ret];
}

#pragma mark - Private

- (void)failWithErrorCode:(AudioStreamerErrorCode)anErrorCode {
  if (bufferManager != nil) {
    [bufferManager abortPendingData];
  }
  AudioStreamerStateController *controller = self.stateController;
  NSParameterAssert(controller != nil);
  if (![controller performBlockOnTargetQueue:^{
          [self handleFailureSynchronouslyWithCode:anErrorCode];
        }]) {
    return;
  }
  return;
}

- (void)setState:(AudioStreamerState)aStatus {
  AudioStreamerState previousState = state_;
  if (previousState != aStatus) {
    [self applyRetrySideEffectsForState:aStatus];
  }
  AudioStreamerStateController *controller = self.stateController;
  NSParameterAssert(controller != nil);
  [controller transitionToState:aStatus];
}

- (void)handleFailureSynchronouslyWithCode:(AudioStreamerErrorCode)anErrorCode {
  if (errorCode != AS_NO_ERROR) {
    NSLog(@"Already has error, ignoring new error: %d", anErrorCode);
    return;
  }

  BOOL isTransient = [AudioStreamer isErrorCodeTransient:anErrorCode networkError:networkError];
  BOOL willRetry = isTransient && self.retryAttemptCount < self.maxRetryCount;
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:3];
  userInfo[ASStreamErrorCodeKey] = @(anErrorCode);
  userInfo[ASStreamErrorIsTransientKey] = @(willRetry);
  if (networkError != nil) {
    userInfo[ASStreamErrorUnderlyingErrorKey] = networkError;
  }
  [[NSNotificationCenter defaultCenter]
      postNotificationName:ASStreamErrorInfoNotification
                    object:self
                  userInfo:userInfo];

  if (willRetry) {
    [self scheduleRetryForError:anErrorCode];
    return;
  }

  self.retryAttemptCount = 0;
  self.retryScheduled = NO;
  self.retryResumeTime = 0.0;
  self.retryGeneration += 1;

  NSLog(@"Audio error: %d", anErrorCode);
  errorCode = anErrorCode;

  [self progress:&lastProgress];

  [self stop];
}

- (void)prepareForRetry {
  [self teardownAudioResources];
  discontinuous = YES;
}

- (void)scheduleRetryForError:(AudioStreamerErrorCode)errorCodeValue {
  self.retryAttemptCount += 1;

  double resume = 0.0;
  if ([self progress:&resume]) {
    self.retryResumeTime = resume;
    lastProgress = resume;
    seekTime = resume;
  } else {
    self.retryResumeTime = 0.0;
  }

  self.retryGeneration += 1;
  NSUInteger generation = self.retryGeneration;
  self.retryScheduled = YES;

  NSTimeInterval delay = self.retryBackoffInterval * (double)self.retryAttemptCount;
  if (delay > HMS_RETRY_BACKOFF_MAX) {
    delay = HMS_RETRY_BACKOFF_MAX;
  }

  NSLog(@"Transient audio error %d, scheduling retry attempt %lu/%lu in %.2f seconds",
        errorCodeValue,
        (unsigned long)self.retryAttemptCount,
        (unsigned long)self.maxRetryCount,
        delay);

  [self setState:AS_WAITING_FOR_DATA];
  [self prepareForRetry];

  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    if (generation != strongSelf.retryGeneration) {
      return;
    }
    strongSelf.retryScheduled = NO;
    if (strongSelf->state_ == AS_STOPPED || strongSelf->state_ == AS_DONE) {
      return;
    }
    strongSelf->networkError = nil;
    strongSelf->errorCode = AS_NO_ERROR;
    strongSelf->state_ = AS_INITIALIZED;
    if (![strongSelf start]) {
      [strongSelf failWithErrorCode:errorCodeValue];
      return;
    }
  });
}

- (void) checkTimeout {
  /* Ignore if we're in the paused state */
  if (state_ == AS_PAUSED) return;
  /* If the data task has been suspended and not resumed, then this tick
   is irrelevant because we're not trying to read data anyway */
  if (suspended && !resumed) return;
  /* If the data task was suspended and then resumed, then we still
   discard this sample (not enough of it was known to be in the "active
   state"), but we clear flags so we might process the next sample */
  if (resumed && suspended) {
    suspended = NO;
    resumed = NO;
    return;
  }
  
  /* events happened? no timeout. */
  if (events > 0) {
    events = 0;
    return;
  }
  
  networkError = [NSError errorWithDomain:@"Timed out" code:1 userInfo:nil];
  [self failWithErrorCode:AS_TIMED_OUT];
}

+ (AudioFileTypeID)hintForFileExtension:(NSString *)fileExtension {
  return [AudioStreamerMetadata hintForFileExtension:fileExtension];
}

+ (AudioFileTypeID) hintForMIMEType:(NSString*)mimeType {
  return [AudioStreamerMetadata hintForMIMEType:mimeType];
}

- (BOOL)openURLSession {
  if (session != NULL) {
    NSLog(@"openURLSession: Session already exists");
    return NO;
  }
  
  // Create session configuration
  NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
  sessionConfig.timeoutIntervalForRequest = timeoutInterval;
  sessionConfig.timeoutIntervalForResource = timeoutInterval * 2;
  
  // Configure proxy if needed
  if (proxyType != PROXY_SYSTEM) {
    if (proxyType == PROXY_HTTP) {
      sessionConfig.connectionProxyDictionary = @{
          (NSString *)kCFNetworkProxiesHTTPEnable: @YES,
          (NSString *)kCFNetworkProxiesHTTPProxy: proxyHost,
          (NSString *)kCFNetworkProxiesHTTPPort: @(proxyPort),
          (NSString *)kCFNetworkProxiesHTTPSEnable: @YES,
          (NSString *)kCFNetworkProxiesHTTPSProxy: proxyHost,
          (NSString *)kCFNetworkProxiesHTTPSPort: @(proxyPort)
      };
    } else if (proxyType == PROXY_SOCKS) {
      sessionConfig.connectionProxyDictionary = @{
          (NSString *)kCFNetworkProxiesSOCKSEnable: @YES,
          (NSString *)kCFNetworkProxiesSOCKSProxy: proxyHost,
          (NSString *)kCFNetworkProxiesSOCKSPort: @(proxyPort)
      };
    }
  }
  
  // Create session with delegate
  session = [NSURLSession sessionWithConfiguration:sessionConfig
                                         delegate:self
                                    delegateQueue:[NSOperationQueue mainQueue]];
  
  if (!session) {
    NSLog(@"Failed to create URL session");
    return NO;
  }
  
  // Create request
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  
  // Handle seeking if needed
  if (fileLength > 0 && seekByteOffset > 0) {
    NSString *rangeValue = [NSString stringWithFormat:@"bytes=%lld-%lld",
                           seekByteOffset, fileLength - 1];
    [request setValue:rangeValue forHTTPHeaderField:@"Range"];
    discontinuous = YES;
    seekByteOffset = 0;
  }
  
  // Create data task
  dataTask = [session dataTaskWithRequest:request];
  if (!dataTask) {
    NSLog(@"Failed to create data task");
    [session invalidateAndCancel];
    session = nil;
    return NO;
  }
  
  [dataTask resume];
  [self setState:AS_WAITING_FOR_DATA];
  
  return YES;
}

- (void)closeURLSession {
  if (bufferManager != nil) {
    [bufferManager clearQueuedPackets];
  }
  
  // Cancel data task if it exists
  if (dataTask) {
    [dataTask cancel];
    dataTask = nil;
  }
  
  // Invalidate and release session
  if (session) {
    [session invalidateAndCancel];
    session = nil;
  }
}

#pragma mark - NSURLSessionDataDelegate methods

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
  events++;
  
  // Extract HTTP headers
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    httpHeaders = httpResponse.allHeaderFields;
    long long declaredLength = httpResponse.expectedContentLength;
    
    // Only read the content length if we seeked to time zero, otherwise
    // we only have a subset of the total bytes.
    if (seekByteOffset == 0) {
      NSNumber *contentLengthNumber = httpResponse.allHeaderFields[@"Content-Length"];
      if ([contentLengthNumber respondsToSelector:@selector(longLongValue)]) {
        declaredLength = [contentLengthNumber longLongValue];
      }
      fileLength = declaredLength;
    }
    if (declaredLength > 0) {
      self.expectedContentLength = declaredLength;
    }
  }
  
  // Initialize audio file stream if needed
  if (!audioFileStream) {
    // If a file type wasn't specified, we have to guess
    if (fileType == 0) {
      NSString *contentType = [httpHeaders objectForKey:@"Content-Type"];
      fileType = [AudioStreamer hintForMIMEType:contentType];
      if (fileType == 0) {
        fileType = [AudioStreamer hintForFileExtension:[[url path] pathExtension]];
        if (fileType == 0) {
          fileType = kAudioFileMP3Type;
        }
      }
    }

    NSLog(@"Creating AudioFileStream with fileType: 0x%x (%u)", (unsigned int)fileType, (unsigned int)fileType);

    OSStatus openErr = [self openAudioFileStreamWithHint:fileType];
    NSLog(@"AudioFileStreamOpen result: %d", (int)openErr);
    if (openErr) {
      [self failWithErrorCode:AS_FILE_STREAM_OPEN_FAILED];
      completionHandler(NSURLSessionResponseCancel);
      return;
    }
    self.adtsFallbackAttempted = (fileType == kAudioFileAAC_ADTSType);
  }
  
  // Continue with the task
  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveData:(NSData *)data {
  events++;
  
  if ([self isDone]) return;
  
  // We have successfully read data, so clear the "discontinuous" flag
  if (discontinuous) {
    discontinuous = false;
  }
  
  // Process the received data
  NSUInteger length = [data length];
  if (length <= 0) {
    return;
  }
  self.totalBytesReceived += length;
  
  // Parse the data through the audio file stream
  const void *bytes = [data bytes];

  if (!self.parserReadyForPackets) {
    if (self.formatSniffBuffer == nil) {
      self.formatSniffBuffer = [NSMutableData data];
    }
    NSUInteger remainingCapacity = (self.formatSniffBuffer.length < kMaxFormatSniffBytes)
      ? (kMaxFormatSniffBytes - self.formatSniffBuffer.length)
      : 0;
    if (remainingCapacity > 0) {
      NSUInteger copyLength = MIN(length, remainingCapacity);
      [self.formatSniffBuffer appendBytes:bytes length:copyLength];
    }
  }

  OSStatus parseErr;
  if (discontinuous) {
    parseErr = AudioFileStreamParseBytes(audioFileStream, (UInt32)length, bytes,
                                         kAudioFileStreamParseFlag_Discontinuity);
  } else {
    parseErr = AudioFileStreamParseBytes(audioFileStream, (UInt32)length, bytes, 0);
  }

  if (parseErr) {
    if ([self attemptADTSFallbackReplayingBufferedDataWithBytes:bytes
                                                        length:(UInt32)length
                                                         error:parseErr]) {
      return;
    }
    [self failWithErrorCode:AS_FILE_STREAM_PARSE_BYTES_FAILED];
    return;
  }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
  
  // Dispatch to main thread for consistency
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self URLSession:session task:task didCompleteWithError:error];
    });
    return;
  }
  
  BOOL transferIncomplete = NO;
  if (self.expectedContentLength > 0 && self.totalBytesReceived > 0) {
    int64_t shortfall = (int64_t)self.expectedContentLength - (int64_t)self.totalBytesReceived;
    int64_t tolerance = (int64_t)(self.expectedContentLength * kContentLengthToleranceFraction);
    if (tolerance < kContentLengthToleranceMinimum) {
      tolerance = kContentLengthToleranceMinimum;
    }
    transferIncomplete = shortfall > tolerance;
  }
  if (!error && transferIncomplete) {
    error = [NSError errorWithDomain:NSURLErrorDomain
                                code:NSURLErrorNetworkConnectionLost
                            userInfo:@{ NSLocalizedDescriptionKey : @"Stream ended before all bytes were received." }];
  }

  if (error) {
    networkError = error;
    if (bufferManager != nil) {
      [bufferManager abortPendingData];
    }
    [self failWithErrorCode:AS_NETWORK_CONNECTION_FAILED];
    return;
  }
  
  // Successfully completed the download
  [timeout invalidate];
  timeout = nil;
  
  // Flush out extra data if necessary
  if (bufferManager != nil && bufferManager.bytesFilled > 0) {
    AudioBufferManagerEnqueueResult flushResult = [bufferManager flushCurrentBuffer];
    if (flushResult == AudioBufferManagerEnqueueResultFailed) {
      [self failWithErrorCode:AS_AUDIO_QUEUE_ENQUEUE_FAILED];
      return;
    }
  }
  
  // If we never received any packets, then we're done now
  if (state_ == AS_WAITING_FOR_DATA) {
    [self setState:AS_DONE];
  }
  
  // If we have no more queued data, and the stream has reached its end, flush the audio queue
  if (bufferManager == nil || ![bufferManager hasQueuedPackets]) {
    err = AudioQueueFlush(audioQueue);
    if (err) {
      [self failWithErrorCode:AS_AUDIO_QUEUE_FLUSH_FAILED];
      return;
    }
  }
  self.expectedContentLength = -1;
  self.totalBytesReceived = 0;
  self.totalBytesReceived = 0;
}

// Handle task suspension when waiting for buffer
- (void)suspendDataTask {
  if (!suspended) {
    [dataTask suspend];
    suspended = YES;
    resumed = NO;
  }
}

// Handle task resumption when buffer becomes available
- (void)resumeDataTask {
  if (suspended) {
    [dataTask resume];
    suspended = NO;
    resumed = YES;
  }
}

#pragma mark - Audio Queue and Buffer Management

- (void)createQueue {
    [self.stateLock lock];
    
    if (audioQueue != NULL) {
        NSLog(@"Warning: createQueue called but audioQueue already exists");
        [self.stateLock unlock];
        return;
    }
    
    [self.stateLock unlock];
    
    // DEBUG LOGGING:
    NSLog(@"ASBD Format: mFormatID=0x%x, mSampleRate=%.0f, mChannelsPerFrame=%u",
          (unsigned int)asbd.mFormatID, asbd.mSampleRate, (unsigned int)asbd.mChannelsPerFrame);
    NSLog(@"ASBD: mBitsPerChannel=%u, mBytesPerFrame=%u, mFramesPerPacket=%u",
          (unsigned int)asbd.mBitsPerChannel, (unsigned int)asbd.mBytesPerFrame, (unsigned int)asbd.mFramesPerPacket);

    // Log bitrate info if available
    UInt32 bitrate = 0;
    UInt32 bitrateSize = sizeof(bitrate);
    OSStatus bitrateErr = AudioFileStreamGetProperty(audioFileStream,
                                              kAudioFileStreamProperty_BitRate,
                                              &bitrateSize, &bitrate);
    
    if (bitrateErr == 0 && bitrate > 0) {
        NSLog(@"Stream Bitrate: %u bps (%.1f kbps)", (unsigned int)bitrate, bitrate / 1000.0);
    } else {
        NSLog(@"Stream Bitrate: Unknown");
    }

    // Create the audio queue - macOS specific
    // Use NULL for CFRunLoop to avoid Carbon Component Manager issues
    err = AudioQueueNewOutput(&asbd, MyAudioQueueOutputCallback,
                              (__bridge void*) self, NULL, NULL,
                              0, &audioQueue);
    NSLog(@"AudioQueueNewOutput result: %d", (int)err);
    CHECK_ERR(err, AS_AUDIO_QUEUE_CREATION_FAILED);
    
    // Set volume
    Float32 volume = 1.0;
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, volume);
    
    // Add property listener
    err = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning,
                                        MyAudioQueueIsRunningCallback,
                                        (__bridge void*) self);
    NSLog(@"AudioQueueAddPropertyListener result: %d", (int)err);
    CHECK_ERR(err, AS_AUDIO_QUEUE_ADD_LISTENER_FAILED);
    
    // Get packet size properties
    UInt32 sizeOfUInt32 = sizeof(UInt32);
    err = AudioFileStreamGetProperty(audioFileStream,
                                     kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32,
                                     &packetBufferSize);
    
    if (err || packetBufferSize == 0) {
        err = AudioFileStreamGetProperty(audioFileStream,
                                         kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32,
                                         &packetBufferSize);
        if (err || packetBufferSize == 0) {
            packetBufferSize = bufferSize;
        }
    }
    
    // Allocate audio queue buffers
    buffers = malloc(bufferCnt * sizeof(buffers[0]));
    CHECK_ERR(buffers == NULL, AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED);
    
    for (unsigned int i = 0; i < bufferCnt; ++i) {
        err = AudioQueueAllocateBuffer(audioQueue, packetBufferSize,
                                       &buffers[i]);
        CHECK_ERR(err, AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED);
    }
    
    bufferManager = [[AudioBufferManager alloc] initWithBufferCount:bufferCnt
                                                   packetBufferSize:packetBufferSize
                                                    maxPacketDescs:kAQMaxPacketDescs
                                                     bufferInfinite:bufferInfinite
                                                           delegate:self];
    CHECK_ERR(bufferManager == nil, AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED);
    
    // Handle magic cookie
    UInt32 cookieSize;
    Boolean writable;
    OSStatus ignorableError;
    ignorableError = AudioFileStreamGetPropertyInfo(audioFileStream,
                                                    kAudioFileStreamProperty_MagicCookieData, &cookieSize,
                                                    &writable);
    if (ignorableError) {
        return;
    }
    
    void *cookieData = calloc(1, cookieSize);
    if (cookieData == NULL) return;
    ignorableError = AudioFileStreamGetProperty(audioFileStream,
                                                kAudioFileStreamProperty_MagicCookieData, &cookieSize,
                                                cookieData);
    if (ignorableError) {
        free(cookieData);
        return;
    }
    
    AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookieData,
                          cookieSize);
    free(cookieData);
}

- (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
ioFlags:(UInt32 *)ioFlags {
  assert(inAudioFileStream == audioFileStream);
  
  switch (inPropertyID) {
    case kAudioFileStreamProperty_ReadyToProducePackets:
      LOG(@"ready for packets");
      discontinuous = true;
      self.parserReadyForPackets = YES;
      self.formatSniffBuffer = nil;
      break;
      
    case kAudioFileStreamProperty_DataOffset: {
      SInt64 offset;
      UInt32 offsetSize = sizeof(offset);
      err = AudioFileStreamGetProperty(inAudioFileStream,
                                       kAudioFileStreamProperty_DataOffset, &offsetSize, &offset);
      CHECK_ERR(err, AS_FILE_STREAM_GET_PROPERTY_FAILED);
      dataOffset = offset;
      
      if (audioDataByteCount) {
        fileLength = dataOffset + audioDataByteCount;
      }
      LOG(@"have data offset: %llx", dataOffset);
      break;
    }
      
    case kAudioFileStreamProperty_AudioDataByteCount: {
      UInt32 byteCountSize = sizeof(UInt64);
      err = AudioFileStreamGetProperty(inAudioFileStream,
                                       kAudioFileStreamProperty_AudioDataByteCount,
                                       &byteCountSize, &audioDataByteCount);
      CHECK_ERR(err, AS_FILE_STREAM_GET_PROPERTY_FAILED);
      fileLength = dataOffset + audioDataByteCount;
      LOG(@"have byte count: %llx", audioDataByteCount);
      break;
    }
      
    case kAudioFileStreamProperty_DataFormat: {
      /* If we seeked, don't re-read the data */
      if (asbd.mSampleRate == 0) {
        UInt32 asbdSize = sizeof(asbd);
        
        err = AudioFileStreamGetProperty(inAudioFileStream,
                                         kAudioFileStreamProperty_DataFormat, &asbdSize, &asbd);
        CHECK_ERR(err, AS_FILE_STREAM_GET_PROPERTY_FAILED);
      }
      LOG(@"have data format");
      break;
    }
  }
}

- (void)handleAudioPackets:(const void*)inInputData
numberBytes:(UInt32)inNumberBytes
numberPackets:(UInt32)inNumberPackets
packetDescriptions:(AudioStreamPacketDescription*)inPacketDescriptions {
  if ([self isDone]) return;
  // we have successfully read the first packets from the audio stream, so
  // clear the "discontinuous" flag
  if (discontinuous) {
    discontinuous = false;
  }
  
  if (!audioQueue) {
    [self createQueue];
  }
  if (!bufferManager) return;

  assert(inPacketDescriptions != NULL);

  const uint8_t *inputBytes = (const uint8_t *)inInputData;
  UInt32 i;
  for (i = 0; i < inNumberPackets; i++) {
    AudioStreamPacketDescription desc = inPacketDescriptions[i];
    const void *packetData = inputBytes + desc.mStartOffset;

    if (!self.startupBufferSatisfied &&
        !self.hasAudioQueueStarted &&
        asbd.mSampleRate > 0) {
      double frames = desc.mVariableFramesInPacket;
      if (frames == 0 && asbd.mFramesPerPacket > 0) {
        frames = asbd.mFramesPerPacket;
      }
      if (frames > 0) {
        self.startupBufferedDuration += frames / asbd.mSampleRate;
        if (self.startupBufferedDuration >= kStartupBufferSeconds) {
          self.startupBufferSatisfied = YES;
        }
      }
    }

    AudioBufferManagerEnqueueResult result =
      [bufferManager handlePacketData:packetData description:desc];
    CHECK_ERR(result == AudioBufferManagerEnqueueResultFailed, AS_AUDIO_QUEUE_ENQUEUE_FAILED);

    if (result == AudioBufferManagerEnqueueResultBlocked) {
      break;
    }

    UInt64 packetSize = desc.mDataByteSize;
    processedPacketsSizeTotal += packetSize;
    processedPacketsCount++;
    if (processedPacketsCount > BitRateEstimationMinPackets &&
        !bitrateNotification) {
      bitrateNotification = true;
      [[NSNotificationCenter defaultCenter]
       postNotificationName:ASBitrateReadyNotification
       object:self];
    }
  }
  if (i == inNumberPackets) return;

  for (; i < inNumberPackets; i++) {
    AudioStreamPacketDescription desc = inPacketDescriptions[i];
    UInt32 size = desc.mDataByteSize;
    const void *packetData = inputBytes + desc.mStartOffset;
    [bufferManager cachePacketData:packetData packetSize:size description:desc];
  }
}

- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer {
    // For macOS, we can safely handle this on the audio thread, but dispatch state changes to main
    assert(inAQ == audioQueue);
    
    // Find buffer index
    UInt32 idx;
    for (idx = 0; idx < bufferCnt; idx++) {
        if (buffers[idx] == inBuffer) break;
    }
    assert(idx >= 0 && idx < bufferCnt);
    
    LOG(@"buffer %d finished", idx);
    
    [self.stateLock lock];
    BOOL shouldProcessCachedData = NO;
    UInt32 currentBuffersUsed = 0;
    BOOL hasQueuedPackets = NO;
    if (bufferManager != nil) {
        shouldProcessCachedData = [bufferManager bufferCompletedAtIndex:idx];
        currentBuffersUsed = bufferManager.buffersUsed;
        hasQueuedPackets = [bufferManager hasQueuedPackets];
    }
    AudioStreamerState currentState = state_;
    [self.stateLock unlock];
    
    if (currentState == AS_STOPPED) {
        return;
    }
    
    // Check if we're completely done
    if (currentBuffersUsed == 0 && !hasQueuedPackets &&
        dataTask.state == NSURLSessionTaskStateCompleted) {
        AudioQueueStop(audioQueue, false);
    } else if (shouldProcessCachedData) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self isDone]) return;
            if (self->bufferManager != nil) {
                [self->bufferManager processQueuedPackets];
            }
        });
    }
}

- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID {
    assert(inID == kAudioQueueProperty_IsRunning);
    
    [self.stateLock lock];
    AudioStreamerState currentState = state_;
    BOOL currentSeeking = seeking;
    [self.stateLock unlock];
    
    if (currentState == AS_WAITING_FOR_QUEUE_TO_START) {
        // Dispatch state change to main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setState:AS_PLAYING];
        });
    } else {
        UInt32 running;
        UInt32 output = sizeof(running);
        OSStatus err = AudioQueueGetProperty(audioQueue, kAudioQueueProperty_IsRunning,
                                           &running, &output);
        if (!err && !running && !currentSeeking) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setState:AS_DONE];
            });
        }
    }
}

- (OSStatus)audioBufferManager:(AudioBufferManager *)manager
        enqueueBufferAtIndex:(UInt32)bufferIndex
                 bytesFilled:(UInt32)bytesFilledValue
               packetsFilled:(UInt32)packetsFilledValue
          packetDescriptions:(AudioStreamPacketDescription *)packetDescsValue {
  AudioQueueBufferRef fillBuf = buffers[bufferIndex];
  fillBuf->mAudioDataByteSize = bytesFilledValue;
  return AudioQueueEnqueueBuffer(audioQueue, fillBuf, packetsFilledValue,
                                 packetDescsValue);
}

- (void)audioBufferManager:(AudioBufferManager *)manager
             copyPacketData:(const void *)packetData
                 packetSize:(UInt32)packetSize
              toBufferIndex:(UInt32)bufferIndex
                     offset:(UInt32)offset {
  if (packetSize == 0) return;
  AudioQueueBufferRef bufferRef = buffers[bufferIndex];
  memcpy(bufferRef->mAudioData + offset, packetData, packetSize);
}

- (void)audioBufferManagerSuspendData:(AudioBufferManager *)manager {
  [self suspendDataTask];
}

- (void)audioBufferManagerResumeData:(AudioBufferManager *)manager {
  [self resumeDataTask];
}

- (BOOL)audioBufferManagerShouldStartQueue:(AudioBufferManager *)manager {
  if (state_ != AS_WAITING_FOR_DATA) {
    return NO;
  }
  if (self.hasAudioQueueStarted) {
    return NO;
  }
  if (!self.startupBufferSatisfied) {
    UInt32 requiredBuffers = bufferCnt < kStartupBufferMinimumBuffers
      ? bufferCnt
      : kStartupBufferMinimumBuffers;
    if (requiredBuffers == 0) {
      requiredBuffers = 1;
    }
    if (self.startupBufferedDuration >= kStartupBufferSeconds &&
        manager.buffersUsed >= requiredBuffers) {
      self.startupBufferSatisfied = YES;
    } else {
      return NO;
    }
  }
  return YES;
}

- (void)audioBufferManagerStartQueue:(AudioBufferManager *)manager {
  err = AudioQueueStart(audioQueue, NULL);
  if (err) {
    [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
    return;
  }
  self.startupBufferSatisfied = YES;
  self.hasAudioQueueStarted = YES;
  [self setState:AS_WAITING_FOR_QUEUE_TO_START];
}

- (NSString *)description {
  NSMutableString *description = [[NSString stringWithFormat:@"%@", [super description]] mutableCopy];

  if (asbd.mSampleRate != 0) {
    // based on https://developer.apple.com/library/ios/documentation/MusicAudio/Conceptual/AudioUnitHostingGuide_iOS/ConstructingAudioUnitApps/ConstructingAudioUnitApps.html#//apple_ref/doc/uid/TP40009492-CH16-SW29
    char formatIDString[5];
    UInt32 formatID = CFSwapInt32HostToBig(asbd.mFormatID);
    bcopy(&formatID, formatIDString, 4);
    formatIDString[4] = '\0';

    [description appendFormat:@" %.1f KHz '%s'", asbd.mSampleRate / 1000., formatIDString];
  }

  double bitRate;
  if ([self calculatedBitRate:&bitRate])
    [description appendFormat:@" ~%.0f Kbps", round(bitRate / 1000.)];

  return [description copy];
}

#pragma mark - Testing hooks

- (void)simulateErrorForTesting:(AudioStreamerErrorCode)code {
  [self failWithErrorCode:code];
}

- (void)runBufferHealthMonitorOnceWithRunLoop:(NSRunLoop *)runLoop {
  if (runLoop == nil) {
    return;
  }
  void (^driveTimer)(void) = ^{
    [self startBufferHealthMonitor];
    NSTimer *timer = self.bufferHealthTimer;
    if (timer != nil) {
      [timer fire];
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.05];
    [runLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    [self stopBufferHealthMonitor];
  };
  if (runLoop == [NSRunLoop mainRunLoop] && ![NSThread isMainThread]) {
    dispatch_sync(dispatch_get_main_queue(), driveTimer);
  } else {
    driveTimer();
  }
}

- (void)applyRetrySideEffectsForState:(AudioStreamerState)newState {
  switch (newState) {
    case AS_PLAYING:
      self.retryAttemptCount = 0;
      self.retryScheduled = NO;
      self.retryResumeTime = 0.0;
      self.playbackStartTimestamp = CFAbsoluteTimeGetCurrent();
      [self startBufferHealthMonitor];
      break;
    case AS_STOPPED:
      self.retryScheduled = NO;
      self.retryResumeTime = 0.0;
      [self stopBufferHealthMonitor];
      break;
    case AS_PAUSED:
      [self stopBufferHealthMonitor];
      break;
    default:
      if (newState != AS_WAITING_FOR_QUEUE_TO_START) {
        [self stopBufferHealthMonitor];
      }
      break;
  }
}

- (OSStatus)openAudioFileStreamWithHint:(AudioFileTypeID)hint {
  if (audioFileStream) {
    AudioFileStreamClose(audioFileStream);
    audioFileStream = nil;
  }
  self.currentFileTypeHint = hint;
  self.parserReadyForPackets = NO;
  if (self.formatSniffBuffer == nil) {
    self.formatSniffBuffer = [NSMutableData data];
  } else {
    [self.formatSniffBuffer setLength:0];
  }
  OSStatus openErr = AudioFileStreamOpen((__bridge void *)self,
                                         MyPropertyListenerProc,
                                         MyPacketsProc,
                                         hint,
                                         &audioFileStream);
  if (openErr) {
    self.formatSniffBuffer = nil;
    self.currentFileTypeHint = 0;
  }
  return openErr;
}

- (BOOL)attemptADTSFallbackReplayingBufferedDataWithBytes:(const void *)bytes
                                                   length:(UInt32)length
                                                    error:(OSStatus)error {
  if (self.adtsFallbackAttempted ||
      self.parserReadyForPackets ||
      self.currentFileTypeHint == kAudioFileAAC_ADTSType) {
    return NO;
  }

  self.adtsFallbackAttempted = YES;
  NSLog(@"AudioFileStream parse failed with error %d using hint 0x%x; retrying with ADTS",
        (int)error,
        (unsigned int)self.currentFileTypeHint);

  NSMutableData *replayData = self.formatSniffBuffer;
  if (replayData == nil && bytes != NULL && length > 0) {
    replayData = [NSMutableData dataWithBytes:bytes length:length];
  }

  OSStatus reopenErr = [self openAudioFileStreamWithHint:kAudioFileAAC_ADTSType];
  if (reopenErr) {
    NSLog(@"ADTS fallback failed to open stream: %d", (int)reopenErr);
    return NO;
  }

  if (replayData.length > 0) {
    OSStatus replayErr = AudioFileStreamParseBytes(audioFileStream,
                                                   (UInt32)replayData.length,
                                                   replayData.bytes,
                                                   kAudioFileStreamParseFlag_Discontinuity);
    if (replayErr) {
      NSLog(@"ADTS fallback replay failed: %d", (int)replayErr);
      return NO;
    }
  }

  return YES;
}

- (void)startBufferHealthMonitor {
  if (self.bufferHealthTimer != nil) {
    return;
  }
  if ([NSThread isMainThread]) {
    [self installBufferHealthTimerIfNeeded];
    return;
  }
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.bufferHealthTimer != nil) {
      return;
    }
    [strongSelf installBufferHealthTimerIfNeeded];
  });
}

- (void)stopBufferHealthMonitor {
  if (self.bufferHealthTimer == nil) {
    return;
  }
  if ([NSThread isMainThread]) {
    [self invalidateBufferHealthTimer];
    return;
  }
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    [strongSelf invalidateBufferHealthTimer];
  });
}

- (void)installBufferHealthTimerIfNeeded {
  if (self.bufferHealthTimer != nil) {
    return;
  }
  self.bufferHealthTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                            target:self
                                                          selector:@selector(checkBufferHealth)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)invalidateBufferHealthTimer {
  if (self.bufferHealthTimer == nil) {
    return;
  }
  [self.bufferHealthTimer invalidate];
  self.bufferHealthTimer = nil;
}

- (void)checkBufferHealth {
  if (state_ != AS_PLAYING) {
    [self stopBufferHealthMonitor];
    return;
  }
  if (self.retryScheduled) {
    return;
  }
  if (bufferManager == nil) {
    return;
  }
  UInt32 used = bufferManager.buffersUsed;
  if (used >= 2) {
    return;
  }
  if (dataTask && dataTask.state == NSURLSessionTaskStateRunning) {
    return;
  }
  NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - self.playbackStartTimestamp;
  if (elapsed < kStartupBufferSeconds) {
    return;
  }
  [self failWithErrorCode:AS_TIMED_OUT];
}

@end
