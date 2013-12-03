/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSXMLHttpRequest.h"

@interface FSParseRssPodcastFeedRequest : FSXMLHttpRequest {
    NSMutableArray *_playlistItems;
}

@property (readonly) NSMutableArray *playlistItems;

@end