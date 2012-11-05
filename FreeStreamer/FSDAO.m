/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSDAO.h"
#import "FSPlaylistItem.h"

/*
 * A DAO for the purpose of loading some mock data.
 *
 * In a real application (this is just a demonstration), you probably
 * want to use a SQLite database, and make the DAO to load/store the playlists
 * from there.
 */

@implementation FSDAO

- (id)init {
    self = [super init];
    if (self) {
        // Initialization code here.
        NSString *sourcePath = [[NSBundle mainBundle] pathForResource:@"playlists" ofType:@"txt"];
        _data = [[NSString alloc] initWithContentsOfFile:sourcePath
                                          encoding:NSUTF8StringEncoding
                                                   error:nil];
        _playlistItems = [[NSMutableArray alloc] init];
        [self parseData];
    }
    
    return self;
}

- (void)dealloc {
    _data = nil;
    _playlistItems = nil;
}

- (void)parseData {
    BOOL titleLine = NO;
    FSPlaylistItem *item = nil;
    
    [_playlistItems removeAllObjects];
    
    for (NSString *line in [_data componentsSeparatedByString:@"\n"]) {
        NSString *data = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if (!([data length] > 0)) {
            if (item) {
                item = nil;
            }
            goto out;
        }
        
        if ((titleLine = !titleLine)) {
            item = [[FSPlaylistItem alloc] init];
            item.title = data;
        } else {
            item.url = data;
            [_playlistItems addObject:item];
            item = nil;
        }
    }
    
out:
    if (item) {
        [_playlistItems addObject:item];
        item = nil;        
    }
}

- (NSMutableArray *)playlistItems {
	NSMutableArray *items = [[NSMutableArray alloc] init];
	
    [items addObjectsFromArray:_playlistItems];
    
	return items;
}

@end
