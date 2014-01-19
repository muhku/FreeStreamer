/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import "FSParsePlaylistFeedRequest.h"
#import "FSPlaylistItem.h"

static NSString *const kXPathQueryPlaylists = @"/rss/channel/item";

@interface FSParsePlaylistFeedRequest (PrivateMethods)
- (void)parsePlaylists:(xmlNodePtr)node;
@end

@implementation FSParsePlaylistFeedRequest

- (void)parsePlaylists:(xmlNodePtr)node
{
    FSPlaylistItem *playlistItem = [[FSPlaylistItem alloc] init];
    
    for (xmlNodePtr n = node->children; n != NULL; n = n->next) {
        NSString *nodeName = @((const char *)n->name);
        
        if ([nodeName isEqualToString:@"title"]) {
            playlistItem.title = [self contentForNode:n];
        } else if ([nodeName isEqualToString:@"link"]) {
            playlistItem.url = [self contentForNode:n];
        }
    }
    
    [_playlistItems addObject:playlistItem];
}

- (void)parseResponseData
{
    if (!_playlistItems) {
        _playlistItems = [[NSMutableArray alloc] init];
    }
    [_playlistItems removeAllObjects];
    
    [self performXPathQuery:kXPathQueryPlaylists];
}

- (void)parseXMLNode:(xmlNodePtr)node xPathQuery:(NSString *)xPathQuery
{
    if ([xPathQuery isEqualToString:kXPathQueryPlaylists]) {
        [self parsePlaylists:node];
    }
}

- (NSArray *)playlistItems
{
    return _playlistItems;
}

@end
