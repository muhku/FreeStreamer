/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <UIKit/UIKit.h>

@class FSPlayerViewController;
@class FSParsePlaylistFeedRequest;

@interface FSPlaylistViewController : UITableViewController<UITableViewDataSource,UITableViewDelegate> {
    NSMutableArray *_playlistItems;
    UINavigationController *_navigationController;
    FSPlayerViewController *_playerViewController;
    FSParsePlaylistFeedRequest *_request;
}

@property (nonatomic,strong) NSMutableArray *playlistItems;
@property (nonatomic,strong) IBOutlet UINavigationController *navigationController;
@property (nonatomic,strong) IBOutlet FSPlayerViewController *playerViewController;

@end
