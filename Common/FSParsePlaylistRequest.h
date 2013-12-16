/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

/**
 * The playlist format.
 */
typedef enum {
    kFSPlaylistFormatNone,
    kFSPlaylistFormatM3U,
    kFSPlaylistFormatPLS
} FSPlaylistFormat;

/**
 * FSParsePlaylistRequest is a class for parsing a playlist. It supports
 * the M3U and PLS formats.
 *
 * To use the class, define the URL for retrieving the playlist using
 * the url property. Then, define the onCompletion and onFailure handlers.
 * To start the request, use the start method.
 */
@interface FSParsePlaylistRequest : NSObject<NSURLConnectionDelegate> {
    NSString *_url;
    NSURLConnection *_connection;
    NSInteger _httpStatus;
    NSMutableData *_receivedData;
    NSMutableArray *_playlistItems;
    FSPlaylistFormat _format;
}

/**
 * The URL of this request.
 */
@property (nonatomic,copy) NSString *url;
/**
 * Called when the playlist parsing is completed.
 */
@property (copy) void (^onCompletion)();
/**
 * Called if the playlist parsing failed.
 */
@property (copy) void (^onFailure)();
/**
 * The playlist items stored in the FSPlaylistItem class.
 */
@property (readonly) NSMutableArray *playlistItems;

/**
 * Starts the request.
 */
- (void)start;
/**
 * Cancels the request.
 */
- (void)cancel;

@end