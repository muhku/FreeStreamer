/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSAudioController.h"
#import "FSAudioStream.h"
#import "FSPlaylistItem.h"

//#define AC_DEBUG 1

#if !defined (AC_DEBUG)
#define AC_TRACE(...) do {} while (0)
#else
#define AC_TRACE(...) NSLog(__VA_ARGS__)
#endif

typedef enum {
    kFSPlaylistFormatNone,
    kFSPlaylistFormatM3U,
    kFSPlaylistFormatPLS
} FSPlaylistFormat;

@interface FSPlaylistPrivate : NSObject {
    FSPlaylistFormat _format;
    NSMutableArray *_playlistItems;
}

@property (nonatomic,assign) FSPlaylistFormat format;
@property (readonly) NSMutableArray *playlistItems;

- (void)parsePlaylistFromData:(NSData *)data;
- (void)parsePlaylistM3U:(NSString *)playlist;
- (void)parsePlaylistPLS:(NSString *)playlist;

@end

@implementation FSPlaylistPrivate

@synthesize format=_format;
@synthesize playlistItems=_playlistItems;

- (id)init {
    if (self = [super init]) {
        _playlistItems = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)parsePlaylistFromData:(NSData *)data {
    NSString *playlistData = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];

    if (self.format == kFSPlaylistFormatM3U) {
        [self parsePlaylistM3U:playlistData];
    } else if (self.format == kFSPlaylistFormatPLS) {
        [self parsePlaylistPLS:playlistData];
    }
    
}

- (void)parsePlaylistM3U:(NSString *)playlist {
    [_playlistItems removeAllObjects];
    
    for (NSString *line in [playlist componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"#"]) {
            /* metadata, skip */
            continue;
        }
        if ([line hasPrefix:@"http://"] ||
            [line hasPrefix:@"https://"]) {
            FSPlaylistItem *item = [[FSPlaylistItem alloc] init];
            item.url = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            [_playlistItems addObject:item];
        }
    }
}

- (void)parsePlaylistPLS:(NSString *)playlist {
    [_playlistItems removeAllObjects];
    
    NSMutableDictionary *props = [[NSMutableDictionary alloc] init];
    
    size_t i = 0;

    for (NSString *rawLine in [playlist componentsSeparatedByString:@"\n"]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (i == 0) {
            if ([[line lowercaseString] hasPrefix:@"[playlist]"]) {
                i++;
                continue;
            } else {
                // Invalid playlist; the first line should indicate that this is a playlist
                return;
            }
        }
        
        // Ignore empty lines
        if ([line length] == 0) {
            i++;
            continue;
        }

        // Not an empty line; so expect that this is a key/value pair
        NSRange r = [line rangeOfString:@"="];
        
        // Invalid format, key/value pair not found
        if (r.length == 0) {
            return;
        }
        
        NSString *key = [[line substringToIndex:r.location] lowercaseString];
        NSString *value = [line substringFromIndex:r.location + 1];
        
        [props setObject:value forKey:key];
        i++;
    }
    
    NSInteger numItems = [[props valueForKey:@"numberofentries"] integerValue];
    
    if (numItems == 0) {
        // Invalid playlist; number of playlist items not defined
        return;
    }
    
    for (i=0; i < numItems; i++) {
        FSPlaylistItem *item = [[FSPlaylistItem alloc] init];
        
        NSString *title = [props valueForKey:[NSString stringWithFormat:@"title%lu", (i+1)]];
        
        item.title = title;
        
        NSString *file = [props valueForKey:[NSString stringWithFormat:@"file%lu", (i+1)]];
        
        if ([file hasPrefix:@"http://"] ||
            [file hasPrefix:@"https://"]) {
            
            item.url = file;
            
            [_playlistItems addObject:item];
        }
    }
}

@end

@interface FSAudioController ()
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
@end

@implementation FSAudioController

-(id)init {
    if (self = [super init]) {
        _url = nil;
        _streamContentTypeChecked = NO;
        _receivedPlaylistData = nil;
        _playlistPrivate = nil;
        _audioStream = [[FSAudioStream alloc] init];
        _playlistPrivate = [[FSPlaylistPrivate alloc] init];
    }
    return self;
}

- (void)dealloc {
    _url = nil;
    _audioStream = nil;
    _receivedPlaylistData = nil;
    _playlistPrivate = nil;
    if (_contentTypeConnection) {
        [_contentTypeConnection cancel];
        _contentTypeConnection = nil;
    }
    if (_playlistRetrieveConnection) {
        [_playlistRetrieveConnection cancel];
        _playlistRetrieveConnection = nil;
    }
}

/*
 * =======================================
 * Public interface
 * =======================================
 */

- (void)play {
    @synchronized (self) {
        if (_streamContentTypeChecked) {            
            [_audioStream play];
            return;
        }
        
        if (_contentTypeConnection || _playlistRetrieveConnection) {
            /* Already checking the stream content type */
            return;
        }
        
        _streamContentTypeChecked = NO;
            
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_url
                                                                   cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                               timeoutInterval:30.0];
        [request setHTTPMethod:@"HEAD"];
        _contentTypeConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
        
        if (!_contentTypeConnection) {
            /* Failed, just try to play */
            _streamContentTypeChecked = YES;
            [_audioStream play];
            return;
        }
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kFsAudioStreamRetrievingURL] forKey:FSAudioStreamNotificationKey_State];
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamStateChangeNotification object:nil userInfo:userInfo];
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
}

- (void)playFromURL:(NSURL*)url {
    self.url = url;
    [self play];
}

- (void)stop {
    [_audioStream stop];
}

- (void)pause {
    [_audioStream pause];
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (void)setUrl:(NSURL *)url {
    @synchronized (self) {
        _url = nil;
    
        if (url && ![url isEqual:_url]) {
            NSURL *copyOfURL = [url copy];
            _url = copyOfURL;
            /* Since the stream URL changed, we don't know
               its content-type */
            _streamContentTypeChecked = NO;
            [_playlistPrivate.playlistItems removeAllObjects];
        }
    
        _audioStream.url = _url;
    }
}

- (NSURL*)url {
    if (!_url) {
        return nil;
    }
    
    NSURL *copyOfURL = [_url copy];
    return copyOfURL;
}

- (FSAudioStream *)stream {
    return _audioStream;
}

/*
 * =======================================
 * NSURLConnectionDelegate
 * =======================================
 */

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    if (_contentTypeConnection) {
        NSString *contentType = response.MIMEType;
        
        if ([contentType isEqualToString:@"audio/x-mpegurl"]) {
            _playlistPrivate.format = kFSPlaylistFormatM3U;
        } else if ([contentType isEqualToString:@"audio/x-scpls"]) {
            _playlistPrivate.format = kFSPlaylistFormatPLS;
        } else if ([contentType isEqualToString:@"text/plain"]) {
            NSString *absoluteUrl = [_url absoluteString];
            
            if ([absoluteUrl hasSuffix:@".m3u"]) {
                _playlistPrivate.format = kFSPlaylistFormatM3U;
            } else if ([absoluteUrl hasSuffix:@".pls"]) {
                _playlistPrivate.format = kFSPlaylistFormatPLS;
            }            
        } else {
            _playlistPrivate.format = kFSPlaylistFormatNone;
        }
        
        [_contentTypeConnection cancel];
        _contentTypeConnection = nil;
        
        if (_playlistPrivate.format == kFSPlaylistFormatNone) {
            /* Not a playlist file, just try to play the stream */
            _streamContentTypeChecked = YES;
            [_audioStream play];
            return;
        }
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_url
                                                            cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                            timeoutInterval:30.0];
        [request setHTTPMethod:@"GET"];
        _playlistRetrieveConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
        
        if (!_playlistRetrieveConnection) {
            /* Failed to retrieve the playlist, just try to play */
            [_audioStream play];
            return;
        }
    } else if (_playlistRetrieveConnection) {
        if (_receivedPlaylistData) {
            _receivedPlaylistData = nil;
        }
        _receivedPlaylistData = [NSMutableData data];
        [_receivedPlaylistData setLength:0];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (_contentTypeConnection) {
        /* ignore any incoming data */
    } else if (_playlistRetrieveConnection) {
        [_receivedPlaylistData appendData:data];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (_contentTypeConnection) {
        AC_TRACE(@"Error when checking content type: %@", [error localizedDescription]);
        
        _contentTypeConnection = nil;
        /* Failed to read the stream's content type, try playing
         the stream anyway */
        _streamContentTypeChecked = YES;
        [_audioStream play];
    } else if (_playlistRetrieveConnection) {
        AC_TRACE(@"Error when retrieving playlist: %@", [error localizedDescription]);
        
        _playlistRetrieveConnection = nil;
        _receivedPlaylistData = nil;
        /* Failed to read the playlist, try playing the stream anyway */
        _streamContentTypeChecked = YES;
        [_audioStream play];
    }    
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (_contentTypeConnection) {
        _contentTypeConnection = nil;
    } else if (_playlistRetrieveConnection) {
        _playlistRetrieveConnection = nil;
        
        [_playlistPrivate parsePlaylistFromData:_receivedPlaylistData];
        
        if ([_playlistPrivate.playlistItems count] > 0) {
            FSPlaylistItem *first = [_playlistPrivate.playlistItems objectAtIndex:0];
            _audioStream.url = first.nsURL;
        }
        
        _streamContentTypeChecked = YES;
        [_audioStream play];
        
        _receivedPlaylistData = nil;
    }
}

@end
