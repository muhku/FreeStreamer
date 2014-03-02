/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>

/**
 * Follow this notification for the audio stream state changes.
 */
extern NSString* const FSAudioStreamStateChangeNotification;
extern NSString* const FSAudioStreamNotificationKey_State;

/**
 * Follow this notification for the audio stream errors.
 */
extern NSString* const FSAudioStreamErrorNotification;
extern NSString* const FSAudioStreamNotificationKey_Error;

/**
 * Follow this notification for the audio stream metadata.
 */
extern NSString* const FSAudioStreamMetaDataNotification;
extern NSString* const FSAudioStreamNotificationKey_MetaData;

/**
 * The audio stream state.
 */
typedef enum {
    kFsAudioStreamRetrievingURL,
    kFsAudioStreamStopped,
    kFsAudioStreamBuffering,
    kFsAudioStreamPlaying,
    kFsAudioStreamSeeking,
    kFSAudioStreamEndOfFile,
    kFsAudioStreamFailed
} FSAudioStreamState;

/**
 * The audio stream errors.
 */
typedef enum {
    kFsAudioStreamErrorNone = 0,
    kFsAudioStreamErrorOpen = 1,
    kFsAudioStreamErrorStreamParse = 2,
    kFsAudioStreamErrorNetwork = 3,
    kFsAudioStreamErrorUnsupportedFormat = 4
} FSAudioStreamError;

@protocol FSPCMAudioStreamDelegate;
@class FSAudioStreamPrivate;

/**
 * The audio stream playback position.
 */
typedef struct {
    unsigned minute;
    unsigned second;
} FSStreamPosition;

/**
 * FSAudioStream is a class for streaming audio files from an URL.
 * It must be directly fed with an URL, which contains audio. That is,
 * playlists or other non-audio formats yield an error.
 *
 * To start playback, the stream must be either initialized with an URL
 * or the playback URL can be set with the url property. The playback
 * is started with the play method. It is possible to pause or stop
 * the stream with the respective methods.
 *
 * Non-continuous streams (audio streams with a known duration) can be
 * seeked with the seekToPosition method.
 */
@interface FSAudioStream : NSObject {
    FSAudioStreamPrivate *_private;
}

/**
 * Initializes the audio stream with an URL.
 *
 * @param url The URL from which the stream data is retrieved.
 */
- (id)initWithUrl:(NSURL *)url;

/**
 * Starts playing the stream. If no playback URL is
 * defined, an error will occur.
 */
- (void)play;

/**
 * Starts playing the stream from the given URL.
 *
 * @param url The URL from which the stream data is retrieved.
 */
- (void)playFromURL:(NSURL*)url;

/**
 * Stops the stream playback.
 */
- (void)stop;

/**
 * If the stream is playing, the stream playback is paused upon calling pause.
 * Otherwise (the stream is paused), calling pause will continue the playback.
 */
- (void)pause;

/**
 * Seeks the stream to a given position. Requires a non-continuous stream
 * (a stream with a known duration).
 *
 * @param position The stream position to seek to.
 */
- (void)seekToPosition:(FSStreamPosition)position;

/**
 * Sets the audio stream volume from 0.0 to 1.0.
 * Note that the overall volume is still constrained by the volume
 * set by the user! So the actual volume cannot be higher
 * than the volume currently set by the user. For example, if
 * requesting a volume of 0.5, then the volume will be 50%
 * lower than the current playback volume set by the user.
 */
- (void)setVolume:(float)volume;

/**
 * Returns the playback status: YES if the stream is playing, NO otherwise.
 */
- (BOOL)isPlaying;

/**
 * The stream URL.
 */
@property (nonatomic,assign) NSURL *url;
/**
 * Determines if strict content type checking  is required. If the audio stream
 * cannot determine that the stream is actually an audio stream, the stream
 * does not play. Disabling strict content type checking bypasses the
 * stream content type checks and tries to play the stream regardless
 * of the content type information given by the server.
 */
@property (nonatomic,assign) BOOL strictContentTypeChecking;
/**
 * Set an output file to store the stream contents to a file.
 */
@property (nonatomic,assign) NSURL *outputFile;
/**
 * Sets a default content type for the stream. Only used when strict content
 * type checking is disabled.
 */
@property (nonatomic,assign) NSString *defaultContentType;
/**
 * The property has the content type of the stream, for instance audio/mpeg.
 */
@property (nonatomic,assign) NSString *contentType;
/**
 * The property has the suggested file extension for the stream based on the stream content type.
 */
@property (nonatomic,assign) NSString *suggestedFileExtension;
/**
 * This property has the current playback position, if the stream is non-continuous.
 * The current playback position cannot be determined for continuous streams.
 */
@property (nonatomic,readonly) FSStreamPosition currentTimePlayed;
/**
 * This property has the duration of the stream, if the stream is non-continuous.
 * Continuous streams do not have a duration.
 */
@property (nonatomic,readonly) FSStreamPosition duration;
/**
 * The property is true if the stream is continuous (no known duration).
 */
@property (nonatomic,readonly) BOOL continuous;
/**
 * Called upon completion of the stream. Note that for continuous
 * streams this is never called.
 */
@property (copy) void (^onCompletion)();
/**
 * Called upon a failure.
 */
@property (copy) void (^onFailure)();
/**
 * The last stream error.
 */
@property (readonly) FSAudioStreamError lastError;
/**
 * Delegate.
 */
@property (nonatomic,unsafe_unretained) IBOutlet id<FSPCMAudioStreamDelegate> delegate;

@end

/**
 * To access the PCM audio data, use this delegate.
 */
@protocol FSPCMAudioStreamDelegate <NSObject>

@optional
/**
 * Called when there are PCM audio samples available. Do not do any blocking operations
 * when you receive the data. Instead, copy the data and process it so that the
 * main event loop doesn't block. Failing to do so may cause glitches to the audio playback.
 */
- (void)audioStream:(FSAudioStream *)audioStream samplesAvailable:(const int16_t *)samples count:(NSUInteger)count;
@end