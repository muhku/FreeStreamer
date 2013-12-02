/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSAudioController.h"
#import "FSAudioStream.h"
#import "FSPlaylistItem.h"
#import "FSCheckAudioFileFormatRequest.h"
#import "FSParsePlaylistRequest.h"

@interface FSAudioController ()
@property (readonly) FSAudioStream *audioStream;
@property (readonly) FSCheckAudioFileFormatRequest *checkAudioFileFormatRequest;
@property (readonly) FSParsePlaylistRequest *parsePlaylistRequest;
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
        _checkAudioFileFormatRequest = nil;
        _parsePlaylistRequest = nil;
        _readyToPlay = NO;
    }
    return self;
}

- (void)dealloc
{
    [_audioStream stop];
    
    if (_checkAudioFileFormatRequest) {
        [_checkAudioFileFormatRequest cancel];
    }
    if (_parsePlaylistRequest) {
        [_parsePlaylistRequest cancel];
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

- (FSCheckAudioFileFormatRequest *)checkAudioFileFormatRequest
{
    return _checkAudioFileFormatRequest;
}

- (FSParsePlaylistRequest *)parsePlaylistRequest
{
    return _parsePlaylistRequest;
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
                FSPlaylistItem *playlistItem = [self.playlistItems objectAtIndex:self.currentPlaylistItemIndex];
                
                _audioStream.url = playlistItem.nsURL;
            }
            
            [self.audioStream play];
            return;
        }
        
        __weak FSAudioController *weakSelf = self;
        
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
        
        _checkAudioFileFormatRequest = [[FSCheckAudioFileFormatRequest alloc] init];
        _checkAudioFileFormatRequest.url = self.url;
        _checkAudioFileFormatRequest.onCompletion = ^() {
            if (weakSelf.checkAudioFileFormatRequest.playlist) {
                // The URL is a playlist; retrieve the contents
                [weakSelf.parsePlaylistRequest start];
            } else {
                // Not a playlist; try directly playing the URL
                
                weakSelf.readyToPlay = YES;
                [weakSelf.audioStream play];
            }
        };
        _checkAudioFileFormatRequest.onFailure = ^() {
            // Failed to check the format; try playing anyway
            
            weakSelf.readyToPlay = YES;
            [weakSelf.audioStream play];
        };
        [_checkAudioFileFormatRequest start];
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kFsAudioStreamRetrievingURL] forKey:FSAudioStreamNotificationKey_State];
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
            [_checkAudioFileFormatRequest cancel], _checkAudioFileFormatRequest = nil;
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
