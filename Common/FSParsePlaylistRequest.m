/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2016 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSParsePlaylistRequest.h"
#import "FSPlaylistItem.h"

@interface FSParsePlaylistRequest ()
- (void)parsePlaylistFromData:(NSData *)data;
- (void)parsePlaylistM3U:(NSString *)playlist;
- (void)parsePlaylistPLS:(NSString *)playlist;
- (NSURL *)parseLocalFileUrl:(NSString *)fileUrl;

@property (readonly) FSPlaylistFormat format;

@end

@implementation FSParsePlaylistRequest

- (id)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (void)start
{
    if (_connection) {
        return;
    }
    
    NSURLRequest *request = [NSURLRequest requestWithURL:self.url
                                             cachePolicy:NSURLRequestUseProtocolCachePolicy
                                         timeoutInterval:10.0];
    
    @synchronized (self) {
        _receivedData = [NSMutableData data];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
        _playlistItems = [[NSMutableArray alloc] init];
        _format = kFSPlaylistFormatNone;
    }
    
    if (!_connection) {
        self.onFailure();
        return;
    }
}

- (void)cancel
{
    if (!_connection) {
        return;
    }
    @synchronized (self) {
        [_connection cancel];
        _connection = nil;
    }
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (NSMutableArray *)playlistItems
{
    return [_playlistItems copy];
}

- (FSPlaylistFormat)format
{
    return _format;
}

/*
 * =======================================
 * Private
 * =======================================
 */

- (void)parsePlaylistFromData:(NSData *)data
{
    NSString *playlistData = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    
    if (_format == kFSPlaylistFormatM3U) {
        [self parsePlaylistM3U:playlistData];
        
        if ([_playlistItems count] == 0) {
            // If we failed to grab any playlist items, still try
            // to parse it in another format; perhaps the server
            // mistakingly identified the playlist format
            
            [self parsePlaylistPLS:playlistData];
        }
    } else if (_format == kFSPlaylistFormatPLS) {
        [self parsePlaylistPLS:playlistData];
        
        if ([_playlistItems count] == 0) {
            // If we failed to grab any playlist items, still try
            // to parse it in another format; perhaps the server
            // mistakingly identified the playlist format
            
            [self parsePlaylistM3U:playlistData];
        }
    }
    
    if ([_playlistItems count] == 0) {
        /*
         * Fail if we failed to parse any items from the playlist.
         */
        self.onFailure();
    }
}

- (void)parsePlaylistM3U:(NSString *)playlist
{
    [_playlistItems removeAllObjects];
    
    for (NSString *line in [playlist componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"#"]) {
            /* metadata, skip */
            continue;
        }
        if ([line hasPrefix:@"http://"] ||
            [line hasPrefix:@"https://"]) {
            FSPlaylistItem *item = [[FSPlaylistItem alloc] init];
            item.url = [NSURL URLWithString:[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
            
            [_playlistItems addObject:item];
        } else if ([line hasPrefix:@"file://"]) {
            FSPlaylistItem *item = [[FSPlaylistItem alloc] init];
            item.url = [self parseLocalFileUrl:line];
            
            [_playlistItems addObject:item];
        }
    }
}

- (void)parsePlaylistPLS:(NSString *)playlist
{
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
        
        props[key] = value;
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
            item.url = [NSURL URLWithString:file];
            
            [_playlistItems addObject:item];
        } else if ([file hasPrefix:@"file://"]) {
            item.url = [self parseLocalFileUrl:file];
            
            [_playlistItems addObject:item];
        }
    }
}

- (NSURL *)parseLocalFileUrl:(NSString *)fileUrl
{
    // Resolve the local bundle URL
    NSString *path = [fileUrl substringFromIndex:7];
    
    NSRange range = [path rangeOfString:@"." options:NSBackwardsSearch];
    
    NSString *fileName = [path substringWithRange:NSMakeRange(0, range.location)];
    NSString *suffix = [path substringWithRange:NSMakeRange(range.location + 1, [path length] - [fileName length] - 1)];
    
    return [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:fileName ofType:suffix]];
}

/*
 * =======================================
 * NSURLConnectionDelegate
 * =======================================
 */

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    _httpStatus = [httpResponse statusCode];
    
    NSString *contentType = response.MIMEType;
    NSString *absoluteUrl = [response.URL absoluteString];
    
    _format = kFSPlaylistFormatNone;
    
    if ([contentType isEqualToString:@"audio/x-mpegurl"] ||
        [contentType isEqualToString:@"application/x-mpegurl"]) {
        _format = kFSPlaylistFormatM3U;
    } else if ([contentType isEqualToString:@"audio/x-scpls"] ||
               [contentType isEqualToString:@"application/pls+xml"]) {
        _format = kFSPlaylistFormatPLS;
    } else if ([contentType isEqualToString:@"text/plain"]) {
        /* The server did not provide meaningful content type;
         last resort: check the file suffix, if there is one */
        
        if ([absoluteUrl hasSuffix:@".m3u"]) {
            _format = kFSPlaylistFormatM3U;
        } else if ([absoluteUrl hasSuffix:@".pls"]) {
            _format = kFSPlaylistFormatPLS;
        }
    }
    
    if (_format == kFSPlaylistFormatNone) {
        [_connection cancel];

#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
        NSLog(@"FSParsePlaylistRequest: Unable to determine the type of the playlist for URL: %@", _url);
#endif
        
        self.onFailure();
    }

    [_receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [_receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    @synchronized (self) {
        _connection = nil;
        _receivedData = nil;
    }
    
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
    NSLog(@"FSParsePlaylistRequest: Connection failed for URL: %@, error %@", _url, [error localizedDescription]);
#endif
    
    self.onFailure();
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    assert(_connection == connection);
    
    @synchronized (self) {
        _connection = nil;
    }
    
    if (_httpStatus != 200) {
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
        NSLog(@"FSParsePlaylistRequest: Unable to receive playlist from URL: %@", _url);
#endif
        
        self.onFailure();
        return;
    }
    
    [self parsePlaylistFromData:_receivedData];
    
    self.onCompletion();
}

@end