//
//  AudioStreamer.m
//  StreamingAudioPlayer
//
//#import <AVFoundation/AVFoundation.h>

#import "AudioStreamer.h"

#define BitRateEstimationMinPackets 50

#define PROXY_SYSTEM 0
#define PROXY_SOCKS  1
#define PROXY_HTTP   2

/* Default number and size of audio queue buffers */
#define kDefaultNumAQBufs 16
#define kDefaultAQDefaultBufSize 2048

#define CHECK_ERR(err, code) {                                                 \
    if (err) { [self failWithErrorCode:code]; return; }                        \
  }

#if defined(DEBUG) && 0
#define LOG(fmt, args...) NSLog(@"%s " fmt, __PRETTY_FUNCTION__, ##args)
#else
#define LOG(...)
#endif

typedef struct queued_packet {
  AudioStreamPacketDescription desc;
  struct queued_packet *next;
  char data[];
} queued_packet_t;

NSString * const ASBitrateReadyNotification = @"ASBitrateReadyNotification";
NSString * const ASStatusChangedNotification = @"ASStatusChangedNotification";
NSString * const ASDidChangeStateDistributedNotification = @"hermes.state";

@interface AudioStreamer ()

- (void)checkTimeout;
- (void)failWithErrorCode:(AudioStreamerErrorCode)anErrorCode;
- (void)setState:(AudioStreamerState)aStatus;


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

/* Woohoo, actual implementation now! */
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

/* AudioQueue callback notifying that a buffer is done, invoked on AudioQueue's
 * own personal threads, not the main thread */
static void MyAudioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer) {
  AudioStreamer* streamer = (__bridge AudioStreamer*)inClientData;
  [streamer handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

/* AudioQueue callback that a property has changed, invoked on AudioQueue's own
 * personal threads like above */
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
  return stream;
}

- (void)dealloc {
  [self stop];
  assert(queued_head == NULL);
  assert(queued_tail == NULL);
  assert(timeout == nil);
  assert(buffers == NULL);
  assert(inuse == NULL);
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
    default:
      break;
  }

  return @"Audio streaming failed";
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

- (BOOL) start {
  if (session != NULL) return NO;
  assert(audioQueue == NULL);
  assert(state_ == AS_INITIALIZED);
  [self openURLSession];
  timeout = [NSTimer scheduledTimerWithTimeInterval:timeoutInterval
                                             target:self
                                           selector:@selector(checkTimeout)
                                           userInfo:nil
                                            repeats:YES];
  return YES;
}

- (BOOL) pause {
  if (state_ != AS_PLAYING) return NO;
  assert(audioQueue != NULL);
  err = AudioQueuePause(audioQueue);
  if (err) {
    [self failWithErrorCode:AS_AUDIO_QUEUE_PAUSE_FAILED];
    return NO;
  }
  [self setState:AS_PAUSED];
  return YES;
}

- (BOOL) play {
  if (state_ != AS_PAUSED) return NO;
  assert(audioQueue != NULL);
  err = AudioQueueStart(audioQueue, NULL);
  if (err) {
    [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
    return NO;
  }
  [self setState:AS_PLAYING];
  return YES;
}

- (void) stop {
  if (![self isDone]) {
    [self setState:AS_STOPPED];
  }

  [timeout invalidate];
  timeout = nil;

  /* Clean up our session */
  [self closeURLSession];
  if (audioFileStream) {
    err = AudioFileStreamClose(audioFileStream);
    assert(!err);
    audioFileStream = nil;
  }
  if (audioQueue) {
    AudioQueueStop(audioQueue, true);
    err = AudioQueueDispose(audioQueue, true);
    assert(!err);
    audioQueue = nil;
  }
  if (buffers != NULL) {
    free(buffers);
    buffers = NULL;
  }
  if (inuse != NULL) {
    free(inuse);
    inuse = NULL;
  }

  httpHeaders      = nil;
  bytesFilled      = 0;
  packetsFilled    = 0;
  seekByteOffset   = 0;
  packetBufferSize = 0;
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
  double sampleRate     = asbd.mSampleRate;
  double packetDuration = asbd.mFramesPerPacket / sampleRate;

  if (packetDuration && processedPacketsCount > BitRateEstimationMinPackets) {
    double averagePacketByteSize = processedPacketsSizeTotal /
                                    processedPacketsCount;
    /* bits/byte x bytes/packet x packets/sec = bits/sec */
    *rate = 8 * averagePacketByteSize / packetDuration;
    return YES;
  }

  return NO;
}

- (BOOL) duration:(double*)ret {
  double calculatedBitRate;
  if (![self calculatedBitRate:&calculatedBitRate]) return NO;
  if (calculatedBitRate == 0 || fileLength == 0) {
    return NO;
  }

  *ret = (fileLength - dataOffset) / (calculatedBitRate * 0.125);
  return YES;
}

#pragma mark - NSURLSession methods

/**
 * @brief Creates a new URL session for streaming audio data
 *
 * The session is currently only compatible with remote HTTP sources. The session
 * opened could possibly be seeked into the middle of the file, or have other
 * things like proxies attached to it.
 *
 * @return YES if the session was opened, or NO if it failed to open
 */
- (BOOL)openURLSession {
  NSAssert(session == NULL, @"Session already initialized");
  
  // macOS audio setup - force modern Core Audio: now in app delegate
  
  // Create session configuration
  NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
  sessionConfig.timeoutIntervalForRequest = timeoutInterval;
  sessionConfig.timeoutIntervalForResource = timeoutInterval * 2;
  
  // Configure proxy if needed
  if (proxyType != PROXY_SYSTEM) {
    if (proxyType == PROXY_HTTP) {
      // For HTTP proxy
      sessionConfig.connectionProxyDictionary = @{
          (NSString *)kCFNetworkProxiesHTTPEnable: @YES,
          (NSString *)kCFNetworkProxiesHTTPProxy: proxyHost,
          (NSString *)kCFNetworkProxiesHTTPPort: @(proxyPort),
          (NSString *)kCFNetworkProxiesHTTPSEnable: @YES,
          (NSString *)kCFNetworkProxiesHTTPSProxy: proxyHost,
          (NSString *)kCFNetworkProxiesHTTPSPort: @(proxyPort)
      };
    } else if (proxyType == PROXY_SOCKS) {
      // For SOCKS proxy
      sessionConfig.connectionProxyDictionary = @{
          (NSString *)kCFNetworkProxiesSOCKSEnable: @YES,
          (NSString *)kCFNetworkProxiesSOCKSProxy: proxyHost,
          (NSString *)kCFNetworkProxiesSOCKSPort: @(proxyPort)
      };
    }
    // Remove this line - it was overriding the previous settings
    // sessionConfig.connectionProxyDictionary = proxySettings;
  }
  
  // Create session with delegate (self)
  session = [NSURLSession sessionWithConfiguration:sessionConfig
                                         delegate:self
                                    delegateQueue:[NSOperationQueue mainQueue]];
  
  // Create request
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  
  // When seeking to a time within the stream, we both already know the file
  // length and the seekByteOffset will be set to know what to send to the
  // remote server
  if (fileLength > 0 && seekByteOffset > 0) {
    NSString *rangeValue = [NSString stringWithFormat:@"bytes=%lld-%lld",
                           seekByteOffset, fileLength - 1];
    [request setValue:rangeValue forHTTPHeaderField:@"Range"];
    discontinuous = YES;
    seekByteOffset = 0;
  }
  
  // Create data task
  dataTask = [session dataTaskWithRequest:request];
  [dataTask resume];
  
  [self setState:AS_WAITING_FOR_DATA];
  
  return YES;
}


/**
 * @brief Closes the URL session and frees all queued data
 */
- (void)closeURLSession {
  if (waitingOnBuffer) waitingOnBuffer = FALSE;
  
  // Free any queued packets
  queued_packet_t *cur = queued_head;
  while (cur != NULL) {
    queued_packet_t *tmp = cur->next;
    free(cur);
    cur = tmp;
  }
  queued_head = queued_tail = NULL;
  
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
  
    - (void)failWithErrorCode:(AudioStreamerErrorCode)anErrorCode {
      
      // Ensure we're on the main thread for consistent state handling
      if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self failWithErrorCode:anErrorCode];
        });
        return;
      }

      // Only set the error once.
      if (errorCode != AS_NO_ERROR) {
        // Instead of asserting, check and handle gracefully
        if (state_ != AS_STOPPED) {
          NSLog(@"Warning: failWithErrorCode: called when state is not AS_STOPPED (current state: %d)", state_);
          [self setState:AS_STOPPED]; // Make sure we're in the stopped state
        }
        return;
      }
      /* Attempt to save our last point of progress */
      [self progress:&lastProgress];
      
      LOG(@"got an error: %@", [AudioStreamer stringForErrorCode:anErrorCode]);
      errorCode = anErrorCode;
      
      [self stop];
    }
    
    - (void)setState:(AudioStreamerState)aStatus {
      
      // Ensure we're on the main thread for UI operations
      if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self setState:aStatus];
        });
        return;
      }

      
      LOG(@"transitioning to state:%d", aStatus);
      
      if (state_ == aStatus) return;
      state_ = aStatus;
      
      [[NSNotificationCenter defaultCenter]
       postNotificationName:ASStatusChangedNotification
       object:self];
      
      NSString *statusString = nil;
      switch (aStatus) {
        case AS_PLAYING:
          statusString = @"playing";
          break;
        case AS_PAUSED:
          statusString = @"paused";
          break;
        case AS_STOPPED:
          statusString = @"stopped";
        default:
          break;
      }
      if (statusString) {
        [[NSDistributedNotificationCenter defaultCenter]
         postNotificationName:ASDidChangeStateDistributedNotification
         object:@"hermes"
         userInfo:@{@"state":statusString}
         deliverImmediately: YES];
      }
    }
    
    /**
     * @brief Check the stream for a timeout, and trigger one if this is a timeout
     *        situation
     */
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
    
    //
    // hintForFileExtension:
    //
    // Generates a first guess for the file type based on the file's extension
    //
    // Parameters:
    //    fileExtension - the file extension
    //
    // returns a file type hint that can be passed to the AudioFileStream
    //
    + (AudioFileTypeID)hintForFileExtension:(NSString *)fileExtension {
      if ([fileExtension isEqual:@"mp3"]) {
        return kAudioFileMP3Type;
      } else if ([fileExtension isEqual:@"wav"]) {
        return kAudioFileWAVEType;
      } else if ([fileExtension isEqual:@"aifc"]) {
        return kAudioFileAIFCType;
      } else if ([fileExtension isEqual:@"aiff"]) {
        return kAudioFileAIFFType;
      }  else if ([fileExtension isEqual:@"mp4"] || [fileExtension isEqual:@"m4a"]) {
        NSLog(@"MP4/M4A detected, using auto-detection");
        return 0;// <-- Try this instead of kAudioFileMPEG4Type
       // return kAudioFileMPEG4Type;
      } else if ([fileExtension isEqual:@"caf"]) {
        return kAudioFileCAFType;
      } else if ([fileExtension isEqual:@"aac"]) {
        return kAudioFileAAC_ADTSType;
      }
      return 0;
    }
    
    /**
     * @brief Guess the file type based on the listed MIME type in the http response
     *
     * Code from:
     * https://github.com/DigitalDJ/AudioStreamer/blob/master/Classes/AudioStreamer.m
     */
    + (AudioFileTypeID) hintForMIMEType:(NSString*)mimeType {
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
        return 0;  // <-- Try this instead of kAudioFileMPEG4Type
       // return kAudioFileMPEG4Type;
      } else if ([mimeType isEqual:@"audio/x-caf"]) {
        return kAudioFileCAFType;
      } else if ([mimeType isEqual:@"audio/aac"] ||
                 [mimeType isEqual:@"audio/aacp"]) {
        return kAudioFileAAC_ADTSType;
      }
      return 0;
    }
    
    /**
     * @brief Creates a new URL session for streaming audio data
     *
     * The session is currently only compatible with remote HTTP sources. The session
     * opened could possibly be seeked into the middle of the file, or have other
     * things like proxies attached to it.
     *
     * @return YES if the session was opened, or NO if it failed to open
     */
    /**
     * @brief Closes the URL session and frees all queued data
     */
#pragma mark - NSURLSessionDataDelegate methods
    
    - (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
    completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
      events++;
      
      // Extract HTTP headers
      if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        httpHeaders = httpResponse.allHeaderFields;
        
        // Only read the content length if we seeked to time zero, otherwise
        // we only have a subset of the total bytes.
        if (seekByteOffset == 0) {
          fileLength = [httpResponse.allHeaderFields[@"Content-Length"] integerValue];
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

        //logging to check audiofilestream filetype detection
        NSLog(@"Creating AudioFileStream with fileType: 0x%x (%u)", (unsigned int)fileType, (unsigned int)fileType);

        // Create an audio file stream parser
        err = AudioFileStreamOpen((__bridge void*) self, MyPropertyListenerProc,
                                  MyPacketsProc, kAudioFileAAC_ADTSType, &audioFileStream);
        NSLog(@"AudioFileStreamOpen result: %d", (int)err);

        CHECK_ERR(err, AS_FILE_STREAM_OPEN_FAILED);
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
      
      // Parse the data through the audio file stream
      const void *bytes = [data bytes];
      if (discontinuous) {
        err = AudioFileStreamParseBytes(audioFileStream, (UInt32)length, bytes,
                                        kAudioFileStreamParseFlag_Discontinuity);
      } else {
        err = AudioFileStreamParseBytes(audioFileStream, (UInt32)length, bytes, 0);
      }
      CHECK_ERR(err, AS_FILE_STREAM_PARSE_BYTES_FAILED);
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

      
      if (error) {
        networkError = error;
        [self failWithErrorCode:AS_NETWORK_CONNECTION_FAILED];
        return;
      }
      
      // Successfully completed the download
      [timeout invalidate];
      timeout = nil;
      
      // Flush out extra data if necessary
      if (bytesFilled) {
        // Disregard return value because we're at the end of the stream anyway
        [self enqueueBuffer];
      }
      
      // If we never received any packets, then we're done now
      if (state_ == AS_WAITING_FOR_DATA) {
        [self setState:AS_DONE];
      }
      
      // If we have no more queued data, and the stream has reached its end, flush the audio queue
      if (queued_head == NULL) {
        err = AudioQueueFlush(audioQueue);
        if (err) {
          [self failWithErrorCode:AS_AUDIO_QUEUE_FLUSH_FAILED];
          return;
        }
      }
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
    
    //
    // enqueueBuffer
    //
    // Called to pass filled audio buffers to the AudioQueue for playback.
    // This function does not return until a buffer is idle for further filling or
    // the AudioQueue is stopped.
    //
    - (int) enqueueBuffer {
      assert(session != NULL);
      
      assert(!inuse[fillBufferIndex]);
      inuse[fillBufferIndex] = true;    // set in use flag
      buffersUsed++;
      
      // enqueue buffer
      AudioQueueBufferRef fillBuf = buffers[fillBufferIndex];
      fillBuf->mAudioDataByteSize = bytesFilled;
      
      assert(packetsFilled > 0);
      err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, packetsFilled,
                                    packetDescs);
      if (err) {
        [self failWithErrorCode:AS_AUDIO_QUEUE_ENQUEUE_FAILED];
        return -1;
      }
      LOG(@"committed buffer %d", fillBufferIndex);
      
      if (state_ == AS_WAITING_FOR_DATA) {
        /* Once we have a small amount of queued data, then we can go ahead and
         * start the audio queue and the file stream should remain ahead of it */
        if (bufferCnt < 3 || buffersUsed > 2) {
          err = AudioQueueStart(audioQueue, NULL);
          if (err) {
            [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
            return -1;
          }
          [self setState:AS_WAITING_FOR_QUEUE_TO_START];
        }
      }
      
      /* move on to the next buffer and reset counters */
      if (++fillBufferIndex >= bufferCnt) fillBufferIndex = 0;
      bytesFilled   = 0;    // reset bytes filled
      packetsFilled = 0;    // reset packets filled
      
      if (inuse[fillBufferIndex]) {
        LOG(@"waiting for buffer %d", fillBufferIndex);
        if (!bufferInfinite) {
          [self suspendDataTask];
        }
        waitingOnBuffer = true;
        return 0;
      }
      return 1;
    }
    
- (void)logBitrateInfo {
    UInt32 bitrate = 0;
    UInt32 bitrateSize = sizeof(bitrate);
    OSStatus err = AudioFileStreamGetProperty(audioFileStream,
                                              kAudioFileStreamProperty_BitRate,
                                              &bitrateSize, &bitrate);
    
    if (err == 0 && bitrate > 0) {
        NSLog(@"Stream Bitrate: %u bps (%.1f kbps)", (unsigned int)bitrate, bitrate / 1000.0);
    } else {
        NSLog(@"Stream Bitrate: Unknown");
    }
}


    //
    // createQueue
    //
    // Method to create the AudioQueue from the parameters gathered by the
    // AudioFileStream.
    //
    // Creation is deferred to the handling of the first audio packet (although
    // it could be handled any time after kAudioFileStreamProperty_ReadyToProducePackets
    // is true).
    //
    - (void)createQueue {
      assert(audioQueue == NULL);
      
      // DEBUG LOGGING:
      NSLog(@"ASBD Format: mFormatID=0x%x, mSampleRate=%.0f, mChannelsPerFrame=%u",
            (unsigned int)asbd.mFormatID, asbd.mSampleRate, (unsigned int)asbd.mChannelsPerFrame);
      NSLog(@"ASBD: mBitsPerChannel=%u, mBytesPerFrame=%u, mFramesPerPacket=%u",
            (unsigned int)asbd.mBitsPerChannel, (unsigned int)asbd.mBytesPerFrame, (unsigned int)asbd.mFramesPerPacket);

      // ADD BITRATE DETECTION:
      [self logBitrateInfo];

    
      // create the audio queue
      // remove cfrunloopgetcurrent	that would cause usage of old carbon content manager
      err = AudioQueueNewOutput(&asbd, MyAudioQueueOutputCallback,
                                (__bridge void*) self, NULL, NULL,
                                0, &audioQueue);
      NSLog(@"AudioQueueNewOutput result: %d", (int)err);  // <-- debug format type
      CHECK_ERR(err, AS_AUDIO_QUEUE_CREATION_FAILED);
      
      // ADD DEBUG HERE:
      NSLog(@"About to add property listener...");
      err = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning,
                                          MyAudioQueueIsRunningCallback,
                                          (__bridge void*) self);
      NSLog(@"AudioQueueAddPropertyListener result: %d", (int)err);
      CHECK_ERR(err, AS_AUDIO_QUEUE_ADD_LISTENER_FAILED);
      
      NSLog(@"About to get packet size properties...");
      UInt32 sizeOfUInt32 = sizeof(UInt32);
      err = AudioFileStreamGetProperty(audioFileStream,
                                       kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32,
                                       &packetBufferSize);
      NSLog(@"PacketSizeUpperBound result: %d, size: %u", (int)err, (unsigned int)packetBufferSize);
      
      if (err || packetBufferSize == 0) {
          err = AudioFileStreamGetProperty(audioFileStream,
                                           kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32,
                                           &packetBufferSize);
          NSLog(@"MaximumPacketSize result: %d, size: %u", (int)err, (unsigned int)packetBufferSize);
          if (err || packetBufferSize == 0) {
              packetBufferSize = bufferSize;
              NSLog(@"Using default buffer size: %u", (unsigned int)packetBufferSize);
          }
      }
      
      NSLog(@"About to allocate buffers...");

      
      // start the queue if it has not been started already
      // listen to the "isRunning" property
      err = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning,
                                          MyAudioQueueIsRunningCallback,
                                          (__bridge void*) self);
      CHECK_ERR(err, AS_AUDIO_QUEUE_ADD_LISTENER_FAILED);
      
      /* Try to determine the packet size, eventually falling back to some
       reasonable default of a size */
    //  UInt32 sizeOfUInt32 = sizeof(UInt32);
      err = AudioFileStreamGetProperty(audioFileStream,
                                       kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32,
                                       &packetBufferSize);
      
      if (err || packetBufferSize == 0) {
        err = AudioFileStreamGetProperty(audioFileStream,
                                         kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32,
                                         &packetBufferSize);
        if (err || packetBufferSize == 0) {
          // No packet size available, just use the default
          packetBufferSize = bufferSize;
        }
      }
      
      // allocate audio queue buffers
      buffers = malloc(bufferCnt * sizeof(buffers[0]));
      CHECK_ERR(buffers == NULL, AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED);
      inuse = calloc(bufferCnt, sizeof(inuse[0]));
      CHECK_ERR(inuse == NULL, AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED);
      for (unsigned int i = 0; i < bufferCnt; ++i) {
        err = AudioQueueAllocateBuffer(audioQueue, packetBufferSize,
                                       &buffers[i]);
        CHECK_ERR(err, AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED);
      }
      
      /* Some audio formats have a "magic cookie" which needs to be transferred from
       the file stream to the audio queue. If any of this fails it's "OK" because
       the stream either doesn't have a magic or error will propagate later */
      
      // get the cookie size
      UInt32 cookieSize;
      Boolean writable;
      OSStatus ignorableError;
      ignorableError = AudioFileStreamGetPropertyInfo(audioFileStream,
                                                      kAudioFileStreamProperty_MagicCookieData, &cookieSize,
                                                      &writable);
      if (ignorableError) {
        return;
      }
      
      // get the cookie data
      void *cookieData = calloc(1, cookieSize);
      if (cookieData == NULL) return;
      ignorableError = AudioFileStreamGetProperty(audioFileStream,
                                                  kAudioFileStreamProperty_MagicCookieData, &cookieSize,
                                                  cookieData);
      if (ignorableError) {
        free(cookieData);
        return;
      }
      
      // set the cookie on the queue. Don't worry if it fails, all we'd to is return
      // anyway
      AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookieData,
                            cookieSize);
      free(cookieData);
    }
    
    //
    // handlePropertyChangeForFileStream:fileStreamPropertyID:ioFlags:
    //
    // Object method which handles implementation of MyPropertyListenerProc
    //
    // Parameters:
    //    inAudioFileStream - should be the same as self->audioFileStream
    //    inPropertyID - the property that changed
    //    ioFlags - the ioFlags passed in
    //
    - (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
    fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
    ioFlags:(UInt32 *)ioFlags {
      assert(inAudioFileStream == audioFileStream);
      
      switch (inPropertyID) {
        case kAudioFileStreamProperty_ReadyToProducePackets:
          LOG(@"ready for packets");
          discontinuous = true;
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
    
    //
    // handleAudioPackets:numberBytes:numberPackets:packetDescriptions:
    //
    // Object method which handles the implementation of MyPacketsProc
    //
    // Parameters:
    //    inInputData - the packet data
    //    inNumberBytes - byte size of the data
    //    inNumberPackets - number of packets in the data
    //    inPacketDescriptions - packet descriptions
    //
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
        assert(!waitingOnBuffer);
        [self createQueue];
      }
      assert(inPacketDescriptions != NULL);
      
      /* Place each packet into a buffer and then send each buffer into the audio
       queue */
      UInt32 i;
      for (i = 0; i < inNumberPackets && !waitingOnBuffer && queued_head == NULL; i++) {
        AudioStreamPacketDescription *desc = &inPacketDescriptions[i];
        int ret = [self handlePacket:(inInputData + desc->mStartOffset)
                                desc:desc];
        CHECK_ERR(ret < 0, AS_AUDIO_QUEUE_ENQUEUE_FAILED);
        if (!ret) break;
      }
      if (i == inNumberPackets) return;
      
      for (; i < inNumberPackets; i++) {
        /* Allocate the packet */
        UInt32 size = inPacketDescriptions[i].mDataByteSize;
        queued_packet_t *packet = malloc(sizeof(queued_packet_t) + size);
        CHECK_ERR(packet == NULL, AS_AUDIO_QUEUE_ENQUEUE_FAILED);
        
        /* Prepare the packet */
        packet->next = NULL;
        packet->desc = inPacketDescriptions[i];
        packet->desc.mStartOffset = 0;
        memcpy(packet->data, inInputData + inPacketDescriptions[i].mStartOffset,
               size);
        
        if (queued_head == NULL) {
          queued_head = queued_tail = packet;
        } else {
          queued_tail->next = packet;
          queued_tail = packet;
        }
      }
    }
    
    - (int) handlePacket:(const void*)data
    desc:(AudioStreamPacketDescription*)desc{
      assert(audioQueue != NULL);
      UInt64 packetSize = desc->mDataByteSize;
      
      /* This shouldn't happen because most of the time we read the packet buffer
       size from the file stream, but if we restored to guessing it we could
       come up too small here */
      if (packetSize > packetBufferSize) return -1;
      
      // if the space remaining in the buffer is not enough for this packet, then
      // enqueue the buffer and wait for another to become available.
      if (packetBufferSize - bytesFilled < packetSize) {
        int hasFreeBuffer = [self enqueueBuffer];
        if (hasFreeBuffer <= 0) {
          return hasFreeBuffer;
        }
        assert(bytesFilled == 0);
        assert(packetBufferSize >= packetSize);
      }
      
      /* global statistics */
      processedPacketsSizeTotal += packetSize;
      processedPacketsCount++;
      if (processedPacketsCount > BitRateEstimationMinPackets &&
          !bitrateNotification) {
        bitrateNotification = true;
        [[NSNotificationCenter defaultCenter]
         postNotificationName:ASBitrateReadyNotification
         object:self];
      }
      
      // copy data to the audio queue buffer
      AudioQueueBufferRef buf = buffers[fillBufferIndex];
      memcpy(buf->mAudioData + bytesFilled, data, packetSize);
      
      // fill out packet description to pass to enqueue() later on
      packetDescs[packetsFilled] = *desc;
      // Make sure the offset is relative to the start of the audio buffer
      packetDescs[packetsFilled].mStartOffset = bytesFilled;
      // keep track of bytes filled and packets filled
      bytesFilled += packetSize;
      packetsFilled++;
      
      /* If filled our buffer with packets, then commit it to the system */
      if (packetsFilled >= kAQMaxPacketDescs) return [self enqueueBuffer];
      return 1;
    }
    
    /**
     * @brief Internal helper for sending cached packets to the audio queue
     *
     * This method is enqueued for delivery when an audio buffer is freed
     */
    - (void) enqueueCachedData {
      if ([self isDone]) return;
      assert(!waitingOnBuffer);
      assert(!inuse[fillBufferIndex]);
      assert(session != NULL);
      LOG(@"processing some cached data");
      
      /* Queue up as many packets as possible into the buffers */
      queued_packet_t *cur = queued_head;
      while (cur != NULL) {
        int ret = [self handlePacket:cur->data desc:&cur->desc];
        CHECK_ERR(ret < 0, AS_AUDIO_QUEUE_ENQUEUE_FAILED);
        if (ret == 0) break;
        queued_packet_t *next = cur->next;
        free(cur);
        cur = next;
      }
      queued_head = cur;
      
      /* If we finished queueing all our saved packets, we can resume the data task */
      if (cur == NULL) {
        queued_tail = NULL;
        if (!bufferInfinite) {
          [self resumeDataTask];
        }
      }
    }
    
    //
    // handleBufferCompleteForQueue:buffer:
    //
    // Handles the buffer completion notification from the audio queue
    //
    // Parameters:
    //    inAQ - the queue
    //    inBuffer - the buffer
    //
    - (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
    buffer:(AudioQueueBufferRef)inBuffer {
      /* we're only registered for one audio queue... */
      assert(inAQ == audioQueue);
      /* Sanity check to make sure we're on the right thread */
      // thread assertion removed for carbon component manager fix
      //assert([NSThread currentThread] == [NSThread mainThread]);
      
      /* Figure out which buffer just became free, and it had better damn well be
       one of our own buffers */
      UInt32 idx;
      for (idx = 0; idx < bufferCnt; idx++) {
        if (buffers[idx] == inBuffer) break;
      }
      assert(idx >= 0 && idx < bufferCnt);
      assert(inuse[idx]);
      
      LOG(@"buffer %d finished", idx);
      
      /* Signal the buffer is no longer in use */
      inuse[idx] = false;
      buffersUsed--;
      
      /* If we're done with buffers because the stream dying, then there's no need
       * to call more methods on it. */
      if (state_ == AS_STOPPED) {
        return;
      }
      
      /* If there is absolutely no more data which will ever come into the stream,
       * then we're done with the audio */
      else if (buffersUsed == 0 && queued_head == NULL && dataTask.state == NSURLSessionTaskStateCompleted) {
        assert(!waitingOnBuffer);
        AudioQueueStop(audioQueue, false);
        
        /* Otherwise we just opened up a buffer so try to fill it with some cached
         * data if there is any available */
      } else if (waitingOnBuffer) {
        waitingOnBuffer = false;
        [self enqueueCachedData];
      }
    }
    
    //
    // handlePropertyChangeForQueue:propertyID:
    //
    // Implementation for MyAudioQueueIsRunningCallback
    //
    // Parameters:
    //    inAQ - the audio queue
    //    inID - the property ID
    //
    - (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                              propertyID:(AudioQueuePropertyID)inID {
      /* Sanity check to make sure we're on the expected thread */
      //thread assertion removed
     // assert([NSThread currentThread] == [NSThread mainThread]);
      /* We only asked for one property, so the audio queue had better damn well
         only tell us about this property */
      assert(inID == kAudioQueueProperty_IsRunning);

      if (state_ == AS_WAITING_FOR_QUEUE_TO_START) {
        [self setState:AS_PLAYING];
      } else {
        UInt32 running;
        UInt32 output = sizeof(running);
        err = AudioQueueGetProperty(audioQueue, kAudioQueueProperty_IsRunning,
                                    &running, &output);
        if (!err && !running && !seeking) {
          [self setState:AS_DONE];
        }
      }
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

    @end
