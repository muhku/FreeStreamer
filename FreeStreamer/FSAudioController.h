/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

@class FSAudioStream;
@class FSPlaylistPrivate;

@interface FSAudioController : NSObject <NSURLConnectionDelegate> {
    NSURL *_url;
    FSAudioStream *_audioStream;
    
    BOOL _streamContentTypeChecked;
    NSURLConnection *_contentTypeConnection;    
    NSURLConnection *_playlistRetrieveConnection;
    NSMutableData *_receivedPlaylistData;
    
    FSPlaylistPrivate *_playlistPrivate;
}

- (void)play;
- (void)playFromURL:(NSURL*)url;
- (void)stop;
- (void)pause;

@property (nonatomic,weak) NSURL *url;
@property (nonatomic,weak,readonly) FSAudioStream *stream;

@end
