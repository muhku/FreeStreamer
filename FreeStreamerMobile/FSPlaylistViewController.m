/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSPlaylistViewController.h"
#import "FSPlaylistItem.h"
#import "FSPlayerViewController.h"
#import "FSParsePlaylistFeedRequest.h"

@interface FSPlaylistViewController (PrivateMethods)

- (void)addUserPlaylistItems;

@property (nonatomic,readonly) FSParsePlaylistFeedRequest *request;

@end

@implementation FSPlaylistViewController

@synthesize navigationController=_navigationController;
@synthesize playerViewController=_playerViewContoller;
@synthesize playlistItems;
@synthesize userPlaylistItems;

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
    
    _request = [[FSParsePlaylistFeedRequest alloc] init];
    _request.url = @"https://raw.github.com/muhku/FreeStreamer/master/Extra/example-rss-feed.xml";
    _request.onCompletion = ^() {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        
        weakSelf.playlistItems = [[NSMutableArray alloc] initWithArray:weakSelf.request.playlistItems];
        
        [weakSelf addUserPlaylistItems];
        
        [weakSelf.tableView reloadData];
    };
    _request.onFailure = ^() {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:@"Failed to load playlists."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    };
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleDefault;
    self.navigationController.navigationBarHidden = NO;
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [[self playlistItems] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"FreeStreamPlayListItemCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    FSPlaylistItem *item = [[self playlistItems] objectAtIndex:indexPath.row];
    cell.textLabel.text = item.title;
    
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	FSPlaylistItem *item = [[self playlistItems] objectAtIndex:indexPath.row];
    
    self.playerViewController.selectedPlaylistItem = item;
    self.playerViewController.shouldStartPlaying = YES;
    
    [self.navigationController pushViewController:self.playerViewController animated:YES];
}

/*
 * =======================================
 * Private
 * =======================================
 */

- (FSParsePlaylistFeedRequest *)request
{
    return _request;
}

@end
