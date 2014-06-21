/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <Foundation/Foundation.h>

@class FSAudioStream;
@class FSCheckContentTypeRequest;
@class FSParsePlaylistRequest;
@class FSParseRssPodcastFeedRequest;
@class FSPlaylistItem;

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
    NSURL *_url;
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
- (id)initWithUrl:(NSURL *)url;

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
- (void)playFromURL:(NSURL *)url;

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
 * Sets the audio stream volume from 0.0 to 1.0.
 * Note that the overall volume is still constrained by the volume
 * set by the user! So the actual volume cannot be higher
 * than the volume currently set by the user. For example, if
 * requesting a volume of 0.5, then the volume will be 50%
 * lower than the current playback volume set by the user.
 *
 * @param volume The audio stream volume.
 */
- (void)setVolume:(float)volume;

/**
 * The stream URL.
 */
@property (nonatomic,assign) NSURL *url;
/**
 * The audio stream.
 */
@property (readonly) FSAudioStream *stream;
/**
 * The playlist item the controller is currently using.
 */
@property (nonatomic,readonly) FSPlaylistItem *currentPlaylistItem;

@end