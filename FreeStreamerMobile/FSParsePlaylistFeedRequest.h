/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import "FSXMLHttpRequest.h"

/**
 * The iOS example application uses this class to retrieve the
 * playlist items from an RSS feed. Note that this not utilize
 * any known format but is for demonstration purposes.
 *
 * See the FSXMLHttpRequest class how to form a request to retrieve
 * the feed.
 */
@interface FSParsePlaylistFeedRequest : FSXMLHttpRequest {
    NSMutableArray *_playlistItems;
}

/**
 * The playlist items stored in the FSPlaylistItem class.
 */
@property (strong,nonatomic) NSArray *playlistItems;

@end