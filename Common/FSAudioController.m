/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
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

@synthesize readyToPlay;
@synthesize currentPlaylistItemIndex;
@synthesize playlistItems;

-(id)init
{
    if (self = [super init]) {
        _url = nil;
        _audioStream = [[FSAudioStream alloc] init];
        _checkContentTypeRequest = nil;
        _parsePlaylistRequest = nil;
        _readyToPlay = NO;
    }
    return self;
}

- (id)initWithUrl:(NSString *)url
{
    if (self = [self init]) {
        self.url = url;
    }
    return self;
}

- (void)dealloc
{
    [_audioStream stop];
    
    if (_checkContentTypeRequest) {
        [_checkContentTypeRequest cancel];
    }
    if (_parsePlaylistRequest) {
        [_parsePlaylistRequest cancel];
    }
    if (_parseRssPodcastFeedRequest) {
        [_parseRssPodcastFeedRequest cancel];
    }
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (FSAudioStream *)audioStream
{
    return _audioStream;
}

- (FSCheckContentTypeRequest *)checkContentTypeRequest
{
    return _checkContentTypeRequest;
}

- (FSParsePlaylistRequest *)parsePlaylistRequest
{
    return _parsePlaylistRequest;
}

- (FSParseRssPodcastFeedRequest *)parseRssPodcastFeedRequest
{
    return _parseRssPodcastFeedRequest;
}

- (BOOL)isPlaying
{
    return [_audioStream isPlaying];
}

/*
 * =======================================
 * Public interface
 * =======================================
 */

- (void)play
{
    @synchronized (self) {
        if (self.readyToPlay) {
            if ([self.playlistItems count] > 0) {
                FSPlaylistItem *playlistItem = (self.playlistItems)[self.currentPlaylistItemIndex];
                
                _audioStream.url = playlistItem.nsURL;
            }
            
            [self.audioStream play];
            return;
        }
        
        __weak FSAudioController *weakSelf = self;
        
        /*
         * Handle playlists
         */
        
        _parsePlaylistRequest = [[FSParsePlaylistRequest alloc] init];
        _parsePlaylistRequest.url = self.url;
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
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
        
        /*
         * Handle RSS feed parsing
         */
        
        _parseRssPodcastFeedRequest = [[FSParseRssPodcastFeedRequest alloc] init];
        _parseRssPodcastFeedRequest.url = self.url;
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
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
        
        /*
         * Handle content type check
         */
        
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
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
        [_checkContentTypeRequest start];
        
        NSDictionary *userInfo = @{FSAudioStreamNotificationKey_State: @(kFsAudioStreamRetrievingURL)};
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamStateChangeNotification object:nil userInfo:userInfo];
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
}

- (void)playFromURL:(NSString*)url
{
    self.url = url;
        
    [self play];
}

- (void)stop
{
    [_audioStream stop];
    self.readyToPlay = NO;
}

- (void)pause
{
    [_audioStream pause];
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (void)setUrl:(NSString *)url
{
    @synchronized (self) {
        _url = nil;
        self.currentPlaylistItemIndex = 0;
        
        if (url && ![url isEqual:_url]) {
            [_checkContentTypeRequest cancel], _checkContentTypeRequest = nil;
            [_parsePlaylistRequest cancel], _parsePlaylistRequest = nil;
            
            NSString *copyOfURL = [url copy];
            _url = copyOfURL;
            /* Since the stream URL changed, the content may have changed */
            self.readyToPlay = NO;
            self.playlistItems = [[NSMutableArray alloc] init];
        }
    
        self.audioStream.url = [NSURL URLWithString:_url];
    }
}

- (NSString*)url
{
    if (!_url) {
        return nil;
    }
    
    NSString *copyOfURL = [_url copy];
    return copyOfURL;
}

- (FSAudioStream *)stream
{
    return _audioStream;
}

@end
