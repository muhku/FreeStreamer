/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

typedef enum {
    kFSPlaylistFormatNone,
    kFSPlaylistFormatM3U,
    kFSPlaylistFormatPLS
} FSPlaylistFormat;

@interface FSParsePlaylistRequest : NSObject<NSURLConnectionDelegate> {
    NSString *_url;
    NSURLConnection *_connection;
    NSInteger _httpStatus;
    NSMutableData *_receivedData;
    NSMutableArray *_playlistItems;
    FSPlaylistFormat _format;
}

@property (nonatomic,copy) NSString *url;
@property (copy) void (^onCompletion)();
@property (copy) void (^onFailure)();
@property (readonly) NSMutableArray *playlistItems;
@property (readonly) FSPlaylistFormat format;

- (void)start;
- (void)cancel;

@end