/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import "FSPlaylistViewController.h"
#import "FSPlaylistItem.h"
#import "FSPlayerViewController.h"
#import "FSParseRssPodcastFeedRequest.h"
#import "AJNotificationView.h"

@interface FSPlaylistViewController (PrivateMethods)

- (void)addUserPlaylistItems;

@property (nonatomic,readonly) FSParseRssPodcastFeedRequest *request;

@end

@implementation FSPlaylistViewController

/*
 * =======================================
 * Private
 * =======================================
 */

- (void)addUserPlaylistItems
{
    for (FSPlaylistItem *item in self.userPlaylistItems) {
        BOOL alreadyInPlaylist = NO;
        
        for (FSPlaylistItem *existingItem in self.playlistItems) {
            if ([existingItem isEqual:item]) {
                alreadyInPlaylist = YES;
                break;
            }
        }
        
        if (!alreadyInPlaylist) {
            [self.playlistItems addObject:item];
        }
    }
}

/*
 * =======================================
 * View controller
 * =======================================
 */

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.userPlaylistItems = [[NSMutableArray alloc] init];
    
    __weak FSPlaylistViewController *weakSelf = self;
    
    _request = [[FSParseRssPodcastFeedRequest alloc] init];
    _request.url = [NSURL URLWithString:@"https://raw.github.com/muhku/FreeStreamer/master/Extra/example-rss-feed.xml"];
    _request.onCompletion = ^() {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        
        weakSelf.playlistItems = [[NSMutableArray alloc] initWithArray:weakSelf.request.playlistItems];
        
        [weakSelf addUserPlaylistItems];
        
        [weakSelf.tableView reloadData];
    };
    _request.onFailure = ^() {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        
        [AJNotificationView showNoticeInView:[[[UIApplication sharedApplication] delegate] window]
                                        type:AJNotificationTypeRed
                                       title:@"Failed to load playlists."
                                   hideAfter:10];
    };
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleDefault;
    self.navigationController.navigationBarHidden = NO;
    
    self.view.backgroundColor = [UIColor whiteColor];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    [_request start];
}

/*
 * =======================================
 * Actions
 * =======================================
 */
- (IBAction)addPlaylistItem:(id)sender
{
    UIAlertView * alert = [[UIAlertView alloc]
                           initWithTitle:@"Add Playlist Item"
                           message:@"URL:"
                           delegate:self
                           cancelButtonTitle:@"Cancel" otherButtonTitles:@"Ok", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert show];
}

/*
 * =======================================
 * Alert view delegate
 * =======================================
 */

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 0) {
        return;
    }
    
    NSString *url = [[alertView textFieldAtIndex:0] text];
    
    FSPlaylistItem *item = [[FSPlaylistItem alloc] init];
    item.title = url;
    item.url = url;
    
    for (FSPlaylistItem *existingItem in self.userPlaylistItems) {
        if ([existingItem isEqual:item]) {
            return;
        }
    }
    
    [self.userPlaylistItems addObject:item];
    
    [self addUserPlaylistItems];
    [self.tableView reloadData];
}

/*
 * =======================================
 * Table view
 * =======================================
 */

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return [[self playlistItems] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"FreeStreamPlayListItemCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    FSPlaylistItem *item = [self playlistItems][indexPath.row];
    cell.textLabel.text = item.title;
    
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	FSPlaylistItem *item = [self playlistItems][indexPath.row];
    
    self.playerViewController.selectedPlaylistItem = item;
    self.playerViewController.shouldStartPlaying = YES;
    
    [self.navigationController pushViewController:self.playerViewController animated:YES];
}

/*
 * =======================================
 * Private
 * =======================================
 */

- (FSParseRssPodcastFeedRequest *)request
{
    return _request;
}

@end
