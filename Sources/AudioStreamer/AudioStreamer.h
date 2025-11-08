//
//  AudioStreamer.h
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
//
//  AudioStreamer.h
//  StreamingAudioPlayer
//

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

/* Maximum number of packets which can be contained in one buffer */
#define kAQMaxPacketDescs 512

@class AudioBufferManager;

extern NSString * _Nonnull const ASBitrateReadyNotification;
extern NSString * _Nonnull const ASDidChangeStateDistributedNotification;

NS_ASSUME_NONNULL_BEGIN


typedef enum {
  AS_INITIALIZED = 0,
  AS_WAITING_FOR_DATA,
  AS_WAITING_FOR_QUEUE_TO_START,
  AS_PLAYING,
  AS_PAUSED,
  AS_DONE,
  AS_STOPPED
} AudioStreamerState;

typedef enum
{
  AS_NO_ERROR = 0,
  AS_NETWORK_CONNECTION_FAILED,
  AS_FILE_STREAM_GET_PROPERTY_FAILED,
  AS_FILE_STREAM_SET_PROPERTY_FAILED,
  AS_FILE_STREAM_SEEK_FAILED,
  AS_FILE_STREAM_PARSE_BYTES_FAILED,
  AS_FILE_STREAM_OPEN_FAILED,
  AS_FILE_STREAM_CLOSE_FAILED,
  AS_AUDIO_DATA_NOT_FOUND,
  AS_AUDIO_QUEUE_CREATION_FAILED,
  AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED,
  AS_AUDIO_QUEUE_ENQUEUE_FAILED,
  AS_AUDIO_QUEUE_ADD_LISTENER_FAILED,
  AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED,
  AS_AUDIO_QUEUE_START_FAILED,
  AS_AUDIO_QUEUE_PAUSE_FAILED,
  AS_AUDIO_QUEUE_BUFFER_MISMATCH,
  AS_AUDIO_QUEUE_DISPOSE_FAILED,
  AS_AUDIO_QUEUE_STOP_FAILED,
  AS_AUDIO_QUEUE_FLUSH_FAILED,
  AS_AUDIO_STREAMER_FAILED,
  AS_GET_AUDIO_TIME_FAILED,
  AS_AUDIO_BUFFER_TOO_SMALL,
  AS_TIMED_OUT
} AudioStreamerErrorCode;

typedef enum {
  AS_DONE_STOPPED,
  AS_DONE_ERROR,
  AS_DONE_EOF,
  AS_NOT_DONE
} AudioStreamerDoneReason;

extern NSString * const ASStatusChangedNotification;
extern NSString * const ASStreamErrorInfoNotification;
extern NSString * const ASStreamErrorCodeKey;
extern NSString * const ASStreamErrorIsTransientKey;
extern NSString * const ASStreamErrorUnderlyingErrorKey;

/**
 * This class is implemented on top of Apple's AudioQueue framework. This
 * framework is much too low-level for must use cases, so this class
 * encapsulates the functionality to provide a nicer interface. The interface
 * still requires some management, but it is far more sane than dealing with the
 * AudioQueue structures yourself.
 *
 * This class is essentially a pipeline of three components to get audio to the
 * speakers:
 *
 *              NSURLSession => AudioFileStream => AudioQueue
 *
 * ### NSURLSession
 *
 * The method of reading HTTP data is using NSURLSession which provides modern
 * networking capabilities including background transfers, configuration, and
 * delegate callbacks. All data read from the HTTP stream is piped into the
 * AudioFileStream which then parses all of the data. This stage of the pipeline
 * also flags that events are happening to prevent a timeout. All network
 * activity occurs on a background thread managed by NSURLSession.
 *
 * ### AudioFileStream
 *
 * This stage is implemented by Apple frameworks, and parses all audio data.
 * It is composed of two callbacks which receive data. The first callback invoked
 * in series is one which is notified whenever a new property is known about the
 * audio stream being received. Once all properties have been read, the second
 * callback beings to be invoked, and this callback is responsible for dealing
 * with packets.
 *
 * The second callback is invoked whenever complete "audio packets" are
 * available to send to the audio queue. This stage is invoked on the call stack
 * of the stream which received the data (synchronously with receiving the
 * data).
 *
 * Packets received are buffered in a static set of buffers allocated by the
 * audio queue instance. When a buffer is full, it is committed to the audio
 * queue, and then the next buffer is moved on to. Multiple packets can possibly
 * fit in one buffer. When committing a buffer, if there are no more buffers
 * available, then the data fetch is suspended and all currently received data
 * is stored aside for later processing.
 *
 * ### AudioQueue
 *
 * This final stage is also implemented by Apple, and receives all of the full
 * buffers of data from the AudioFileStream's parsed packets. The implementation
 * manages its own set of threads, but callbacks are invoked on the main thread.
 * The two callbacks that the audio stream is interested in are playback state
 * changing and audio buffers being freed.
 *
 * When a buffer is freed, then it is marked as so, and if the stream was
 * waiting for a buffer to be freed a message to empty the queue as much as
 * possible is sent to the main thread's run loop. Otherwise no extra action
 * need be performed.
 *
 * The main purpose of knowing when the playback state changes is to change the
 * state of the player accordingly.
 */
@interface AudioStreamer : NSObject <NSURLSessionDataDelegate> {
  /* Properties specified before the stream starts. None of these properties
   * should be changed after the stream has started or otherwise it could cause
   * internal inconsistencies in the stream. Detail explanations of each
   * property can be found in the source */
  NSURL           *url;
  NSString        *proxyHost;
  int             proxyPort;
  int             proxyType;  /* defaults to whatever the system says */
  AudioFileTypeID fileType;
  UInt32          bufferSize; /* attempted to be guessed, but fallback here */
  UInt32          bufferCnt;
  BOOL            bufferInfinite;
  int             timeoutInterval;

  /* Created as part of the [start] method */
  NSURLSession *session;
  NSURLSessionDataTask *dataTask;
  
  /* Timeout management */
  NSTimer *timeout; /* timer managing the timeout event */
  BOOL suspended; /* flag if the data task is suspended */
  BOOL resumed; /* flag if the data task was resumed */
  int events;    /* events which have happened since the last tick */

  /* Once the stream has bytes read from it, these are created */
  NSDictionary *httpHeaders;
  AudioFileStreamID audioFileStream;

  /* The audio file stream will fill in these parameters */
  UInt64 fileLength;         /* length of file, set from http headers */
  UInt64 dataOffset;         /* offset into the file of the start of stream */
  UInt64 audioDataByteCount; /* number of bytes of audio data in file */
  AudioStreamBasicDescription asbd; /* description of audio */

  /* Once properties have been read, packets arrive, and the audio queue is
     created once the first packet arrives */
  AudioQueueRef audioQueue;
  UInt32 packetBufferSize;  /* guessed from audioFileStream */

  /* When receiving audio data, raw data is placed into these buffers. The
   * buffers are essentially a "ring buffer of buffers" as each buffer is cycled
   * through and then freed when not in use. Each buffer can contain one or many
   * packets, so the packetDescs array is a list of packets which describes the
   * data in the next pending buffer (used to enqueue data into the AudioQueue
   * structure */
  AudioQueueBufferRef *buffers;
  AudioBufferManager *bufferManager;

  /* Internal metadata about errors and state */
  AudioStreamerState state_;
  AudioStreamerErrorCode errorCode;
  NSError *networkError;
  OSStatus err;

  /* Miscellaneous metadata */
  bool discontinuous;        /* flag to indicate the middle of a stream */
  UInt64 seekByteOffset;     /* position with the file to seek */
  double seekTime;
  bool seeking;              /* Are we currently in the process of seeking? */
  double lastProgress;       /* last calculated progress point */
  UInt64 processedPacketsCount;     /* bit rate calculation utility */
  UInt64 processedPacketsSizeTotal; /* helps calculate the bit rate */
  bool   bitrateNotification;       /* notified that the bitrate is ready */
}

+ (AudioStreamer*) streamWithURL:(NSURL*)url;

@property AudioStreamerErrorCode errorCode;

+ (NSString*) stringForErrorCode:(AudioStreamerErrorCode)anErrorCode;
+ (BOOL)isErrorCodeTransient:(AudioStreamerErrorCode)errorCode
                networkError:(NSError * _Nullable)networkError;

/**
 * Headers received from the remote source
 *
 * Used to determine file size, but other information may be useful as well
 */
@property (readonly, nullable) NSDictionary *httpHeaders;

@property (readonly, nullable) NSError *networkError;

@property (readonly) NSURL *url;

@property (readwrite) UInt32 bufferCnt;

@property (readwrite) UInt32 bufferSize;

@property (readwrite) AudioFileTypeID fileType;

@property (nonatomic, readwrite) BOOL bufferInfinite;

@property (readwrite) int timeoutInterval;

@property (nonatomic, readonly) BOOL retryScheduled;
@property (nonatomic, readonly) NSUInteger retryAttemptCount;
@property (nonatomic, readwrite) NSUInteger maxRetryCount;
@property (nonatomic, readonly) NSTimeInterval retryResumeTime;

- (void)setHTTPProxy:(NSString *)host port:(int)port;

- (void)setSOCKSProxy:(NSString *)host port:(int)port;

- (BOOL) start;

- (void) stop;

- (BOOL) pause;

- (BOOL) play;

- (BOOL) isPlaying;

- (BOOL) isPaused;

- (BOOL) isWaiting;

- (BOOL) isDone;

- (AudioStreamerDoneReason) doneReason;

- (BOOL) seekToTime:(double)newSeekTime;

- (BOOL)calculatedBitRate:(double *)ret;

- (BOOL) setVolume:(double)volume;

- (BOOL)duration:(double *)ret;

- (BOOL)progress:(double *)ret;

NS_ASSUME_NONNULL_END

@end
