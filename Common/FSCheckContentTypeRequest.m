/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import "FSCheckContentTypeRequest.h"

@implementation FSCheckContentTypeRequest

@synthesize url=_url;
@synthesize onCompletion;
@synthesize onFailure;

- (id)init
{
    self = [super init];
    if (self) {
        _format = kFSFileFormatUnknown;
        _playlist = NO;
        _xml = NO;
    }
    return self;
}

- (void)start
{
    if (_connection) {
        return;
    }
    
    _format = kFSFileFormatUnknown;
    _playlist = NO;
    _contentType = @"";
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_url]
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:30.0];
    [request setHTTPMethod:@"HEAD"];
    
    @synchronized (self) {
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    }
    
    if (!_connection) {
        onFailure();
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

- (FSFileFormat)format
{
    return _format;
}

- (NSString *)contentType
{
    return _contentType;
}

- (BOOL)playlist
{
    return _playlist;
}

- (BOOL)xml
{
    return _xml;
}

/*
 * =======================================
 * NSURLConnectionDelegate
 * =======================================
 */

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    _contentType = response.MIMEType;
    
    _format = kFSFileFormatUnknown;
    _playlist = NO;
    
    if ([_contentType isEqualToString:@"audio/mpeg"]) {
        _format = kFSFileFormatMP3;
    } else if ([_contentType isEqualToString:@"audio/x-wav"]) {
        _format = kFSFileFormatWAVE;
    } else if ([_contentType isEqualToString:@"audio/x-aifc"]) {
        _format = kFSFileFormatAIFC;
    } else if ([_contentType isEqualToString:@"audio/x-aiff"]) {
        _format = kFSFileFormatAIFF;
    } else if ([_contentType isEqualToString:@"audio/x-m4a"]) {
        _format = kFSFileFormatM4A;
    } else if ([_contentType isEqualToString:@"audio/mp4"]) {
        _format = kFSFileFormatMPEG4;
    } else if ([_contentType isEqualToString:@"audio/x-caf"]) {
        _format = kFSFileFormatCAF;
    } else if ([_contentType isEqualToString:@"audio/aac"] ||
               [_contentType isEqualToString:@"audio/aacp"]) {
        _format = kFSFileFormatAAC_ADTS;
    } else if ([_contentType isEqualToString:@"audio/x-mpegurl"]) {
        _format = kFSFileFormatM3UPlaylist;
        _playlist = YES;
    } else if ([_contentType isEqualToString:@"audio/x-scpls"]) {
        _format = kFSFileFormatPLSPlaylist;
        _playlist = YES;
    } else if ([_contentType isEqualToString:@"text/plain"]) {
        /* The server did not provide meaningful content type;
           last resort: check the file suffix, if there is one */
        
        NSString *absoluteUrl = [response.URL absoluteString];
        
        if ([absoluteUrl hasSuffix:@".mp3"]) {
            _format = kFSFileFormatMP3;
        } else if ([absoluteUrl hasSuffix:@".mp4"]) {
            _format = kFSFileFormatMPEG4;
        } else if ([absoluteUrl hasSuffix:@".m3u"]) {
            _format = kFSFileFormatM3UPlaylist;
            _playlist = YES;
        } else if ([absoluteUrl hasSuffix:@".pls"]) {
            _format = kFSFileFormatPLSPlaylist;
            _playlist = YES;
        }
    } else if ([_contentType isEqualToString:@"text/xml"] ||
               [_contentType isEqualToString:@"application/xml"]) {
        _format = kFSFileFormatXML;
        _xml = YES;
    }
    
    [_connection cancel];
    _connection = nil;
    
    onCompletion();
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // Do nothing
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    @synchronized (self) {
        _connection = nil;
        _format = kFSFileFormatUnknown;
        _playlist = NO;
    }
    
    onFailure();
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    // Do nothing
}

@end
