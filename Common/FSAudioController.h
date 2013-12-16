/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

@class FSAudioStream;
@class FSCheckContentTypeRequest;
@class FSParsePlaylistRequest;
@class FSParseRssPodcastFeedRequest;

/**
 * FSAudioController is functionally equivalent to FSAudioStream with
 * one addition: it can be directly fed with a playlist (PLS, M3U) URL
 * or an RSS podcast feed. It determines the content type and forms
 * a playlist for playback.
 *
 * Do not use this class but FSAudioStream, if you already know the content type
 * of the URL. Using this class will generate more traffic, as the
 * content type is checked for each URL.
 */
@interface FSAudioController : NSObject {
    NSString *_url;
    FSAudioStream *_audioStream;
    
    BOOL _readyToPlay;
    
    FSCheckContentTypeRequest *_checkContentTypeRequest;
    FSParsePlaylistRequest *_parsePlaylistRequest;
    FSParseRssPodcastFeedRequest *_parseRssPodcastFeedRequest;
}

/**
 * Initializes the audio stream with an URL.
 *
 * @param url The URL from which the stream data is retrieved.
 */
- (id)initWithUrl:(NSString *)url;

/**
 * Starts playing the stream. Before the playback starts,
 * the URL content type is checked and playlists resolved.
 */
- (void)play;

/**
 * Starts playing the stream from an URL. Before the playback starts,
 * the URL content type is checked and playlists resolved.
 *
 * @param url The URL from which the stream data is retrieved.
 */
- (void)playFromURL:(NSString*)url;

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
 * Returns the playback status: YES if the stream is playing, NO otherwise.
 */
- (BOOL)isPlaying;

/**
 * The stream URL.
 */
@property (nonatomic,assign) NSString *url;
/**
 * The audio stream.
 */
@property (readonly) FSAudioStream *stream;

@end