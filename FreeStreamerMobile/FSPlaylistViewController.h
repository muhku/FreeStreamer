/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import <UIKit/UIKit.h>

@class FSPlayerViewController;
@class FSParseRssPodcastFeedRequest;

/**
 * The playlist view controller of the iOS example application.
 *
 * Uses a table view. The table view items are retrieved using the
 * FSParsePlaylistFeedRequest class.
 */
@interface FSPlaylistViewController : UITableViewController<UITableViewDataSource,UITableViewDelegate,UIAlertViewDelegate> {
    FSParseRssPodcastFeedRequest *_request;
}

/**
 * The playlist items displayed in the table view.
 */
@property (nonatomic,strong) NSMutableArray *playlistItems;
/**
 * The user provided playlist items, which are presented in addition to the playlistItems.
 */
@property (nonatomic,strong) NSMutableArray *userPlaylistItems;
/**
 * Reference to a navigation controller.
 */
@property (nonatomic,strong) IBOutlet UINavigationController *navigationController;
/**
 * Reference to a player view controller.
 */
@property (nonatomic,strong) IBOutlet FSPlayerViewController *playerViewController;

/**
 * An IBAction to add a new playlist item.
 *
 * @param sender The sender of the action.
 */
- (IBAction)addPlaylistItem:(id)sender;

@end