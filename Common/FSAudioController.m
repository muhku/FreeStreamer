/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSAudioController.h"
#import "FSAudioStream.h"
#import "FSPlaylistItem.h"
#import "FSCheckContentTypeRequest.h"
#import "FSParsePlaylistRequest.h"
#import "FSParseRssPodcastFeedRequest.h"

@interface FSAudioController ()
@property (readonly) FSAudioStream *audioStream;
@property (readonly) FSCheckContentTypeRequest *checkContentTypeRequest;
@property (readonly) FSParsePlaylistRequest *parsePlaylistRequest;
@property (readonly) FSParseRssPodcastFeedRequest *parseRssPodcastFeedRequest;
@property (nonatomic,assign) BOOL readyToPlay;
@property (nonatomic,assign) NSUInteger currentPlaylistItemIndex;
@property (nonatomic,strong) NSMutableArray *playlistItems;
@end

@implementation FSAudioController

-(id)init
{
    if (self = [super init]) {
        _url = nil;
        _audioStream = nil;
        _checkContentTypeRequest = nil;
        _parsePlaylistRequest = nil;
        _readyToPlay = NO;
    }
    return self;
}

- (id)initWithUrl:(NSURL *)url
{
    if (self = [self init]) {
        self.url = url;
    }
    return self;
}

- (void)dealloc
{
    _audioStream.delegate = nil;
    _audioStream = nil;
    
    [_checkContentTypeRequest cancel];
    [_parsePlaylistRequest cancel];
    [_parseRssPodcastFeedRequest cancel];
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (FSAudioStream *)audioStream
{
    if (!_audioStream) {
        _audioStream = [[FSAudioStream alloc] init];
    }
    return _audioStream;
}

- (FSCheckContentTypeRequest *)checkContentTypeRequest
{
    if (!_checkContentTypeRequest) {
        __weak FSAudioController *weakSelf = self;
        
        _checkContentTypeRequest = [[FSCheckContentTypeRequest alloc] init];
        _checkContentTypeRequest.url = self.url;
        _checkContentTypeRequest.onCompletion = ^() {
            if (weakSelf.checkContentTypeRequest.playlist) {
                // The URL is a playlist; retrieve the contents
                [weakSelf.parsePlaylistRequest start];
            } else if (weakSelf.checkContentTypeRequest.xml) {
                // The URL may be an RSS feed, check the contents
                [weakSelf.parseRssPodcastFeedRequest start];
            } else {
                // Not a playlist; try directly playing the URL
                
                weakSelf.readyToPlay = YES;
                [weakSelf.audioStream play];
            }
        };
        _checkContentTypeRequest.onFailure = ^() {
            // Failed to check the format; try playing anyway
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioController: Failed to check the format, trying to play anyway, URL: %@", weakSelf.audioStream.url);
#endif
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
    }
    return _checkContentTypeRequest;
}

- (FSParsePlaylistRequest *)parsePlaylistRequest
{
    if (!_parsePlaylistRequest) {
        __weak FSAudioController *weakSelf = self;
        
        _parsePlaylistRequest = [[FSParsePlaylistRequest alloc] init];
        _parsePlaylistRequest.onCompletion = ^() {
            if ([weakSelf.parsePlaylistRequest.playlistItems count] > 0) {
                weakSelf.playlistItems = weakSelf.parsePlaylistRequest.playlistItems;
                
                weakSelf.readyToPlay = YES;
                
                weakSelf.audioStream.onCompletion = ^() {
                    if (weakSelf.currentPlaylistItemIndex + 1 < [weakSelf.playlistItems count]) {
                        weakSelf.currentPlaylistItemIndex = weakSelf.currentPlaylistItemIndex + 1;
                        
                        [weakSelf play];
                    }
                };
                
                [weakSelf play];
            }
        };
        _parsePlaylistRequest.onFailure = ^() {
            // Failed to parse the playlist; try playing anyway

#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioController: Playlist parsing failed, trying to play anyway, URL: %@", weakSelf.audioStream.url);
#endif
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
    }
    return _parsePlaylistRequest;
}

- (FSParseRssPodcastFeedRequest *)parseRssPodcastFeedRequest
{
    if (!_parseRssPodcastFeedRequest) {
        __weak FSAudioController *weakSelf = self;
        
        _parseRssPodcastFeedRequest = [[FSParseRssPodcastFeedRequest alloc] init];
        _parseRssPodcastFeedRequest.onCompletion = ^() {
            if ([weakSelf.parseRssPodcastFeedRequest.playlistItems count] > 0) {
                weakSelf.playlistItems = weakSelf.parseRssPodcastFeedRequest.playlistItems;
                
                weakSelf.readyToPlay = YES;
                
                weakSelf.audioStream.onCompletion = ^() {
                    if (weakSelf.currentPlaylistItemIndex + 1 < [weakSelf.playlistItems count]) {
                        weakSelf.currentPlaylistItemIndex = weakSelf.currentPlaylistItemIndex + 1;
                        
                        [weakSelf play];
                    }
                };
                
                [weakSelf play];
            }
        };
        _parseRssPodcastFeedRequest.onFailure = ^() {
            // Failed to parse the XML file; try playing anyway
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioController: Failed to parse the RSS feed, trying to play anyway, URL: %@", weakSelf.audioStream.url);
#endif
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
    }
    return _parseRssPodcastFeedRequest;
}

- (BOOL)isPlaying
{
    return [self.audioStream isPlaying];
}

/*
 * =======================================
 * Public interface
 * =======================================
 */

- (void)play
{
    @synchronized (self) {
        if ([self.url isFileURL] && [self.playlistItems count] == 0) {
            /*
             * Directly play file URLs without checking from network.
             */
            [self.audioStream play];
        } else if (self.stream.cached && [self.playlistItems count] == 0) {
            /*
             * Start playing the cached streams immediately without checking from network.
             */
            [self.audioStream play];
        } else if (self.readyToPlay) {
            /*
             * All prework done; we should have a playable URL for the stream.
             * Start playback.
             */
            if ([self.playlistItems count] > 0) {
                self.audioStream.url = self.currentPlaylistItem.nsURL;
            }
            
            [self.audioStream play];
        } else {
            /*
             * Not ready to play; start by checking the content type of the given
             * URL.
             */
            [self.checkContentTypeRequest start];
        
            NSDictionary *userInfo = @{FSAudioStreamNotificationKey_State: @(kFsAudioStreamRetrievingURL)};
            NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamStateChangeNotification object:nil userInfo:userInfo];
            [[NSNotificationCenter defaultCenter] postNotification:notification];
        }
    }
}

- (void)playFromURL:(NSURL*)url
{
    self.url = url;
        
    [self play];
}

- (void)stop
{
    [self.audioStream stop];
    self.readyToPlay = NO;
}

- (void)pause
{
    [self.audioStream pause];
}

- (void)setVolume:(float)volume
{
    [self.audioStream setVolume:volume];
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (void)setUrl:(NSURL *)url
{
    @synchronized (self) {
        /*
         * The URL set to nil; stop the audio stream.
         */
        if (!url) {
            [self.audioStream stop];
            _url = nil;
            return;
        }
        
        if (![url isEqual:_url]) {
            /*
             * Since the stream URL changed, the stream does not match
             * the currently played URL. Thereby, stop the stream.
             */
            [self.audioStream stop];
            
            /*
             * Reset the content checks as they may be invalid
             * now when the URL changed.
             */
            [self.checkContentTypeRequest cancel];
            [self.parsePlaylistRequest cancel];
            [self.parseRssPodcastFeedRequest cancel];
            
            self.checkContentTypeRequest.url = url;
            self.parsePlaylistRequest.url = url;
            self.parseRssPodcastFeedRequest.url = url;
            
            NSURL *copyOfURL = [url copy];
            _url = copyOfURL;
            
            /*
             * Reset the state.
             */
            self.readyToPlay = NO;
            self.playlistItems = [[NSMutableArray alloc] init];
        }
    
        self.currentPlaylistItemIndex = 0;
        self.audioStream.url = _url;
    }
}

- (NSURL* )url
{
    if (!_url) {
        return nil;
    }
    
    NSURL *copyOfURL = [_url copy];
    return copyOfURL;
}

- (FSAudioStream *)stream
{
    return self.audioStream;
}

- (FSPlaylistItem *)currentPlaylistItem
{
    if (self.readyToPlay) {
        if ([self.playlistItems count] > 0) {
            FSPlaylistItem *playlistItem = (self.playlistItems)[self.currentPlaylistItemIndex];
            return playlistItem;
        }
    }
    return nil;
}

@end