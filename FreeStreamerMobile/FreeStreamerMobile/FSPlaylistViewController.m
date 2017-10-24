/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSPlaylistViewController.h"
#import "FSPlayerViewController.h"
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
    
    _configuration = [[FSStreamConfiguration alloc] init];
    
    self.userPlaylistItems = [[NSMutableArray alloc] init];
    
    __weak FSPlaylistViewController *weakSelf = self;
    
    _diskCachingAllowed = YES;
    
    _request = [[FSParseRssPodcastFeedRequest alloc] init];
    _request.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"example-rss-feed" ofType:@"xml"]];
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
    
    self.navigationController.navigationBar.topItem.title = [[NSString alloc] initWithFormat:@"FreeStreamer %i.%i.%i", FREESTREAMER_VERSION_MAJOR, FREESTREAMER_VERSION_MINOR, FREESTREAMER_VERSION_REVISION];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    if (_diskCachingAllowed) {
        self.diskCacheControl.selectedSegmentIndex = 0;
    } else {
        self.diskCacheControl.selectedSegmentIndex = 1;
    }
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Playlist Item"
                                          message:@"URL:"
                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {}];
    

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                style:UIAlertActionStyleCancel
                                handler:^(UIAlertAction *action) {}]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                style:UIAlertActionStyleDefault
                                handler:^(UIAlertAction *action) {
                                    UITextField *urlTextField = alert.textFields.firstObject;
                                    
                                    NSString *url = [urlTextField text];
                                    
                                    FSPlaylistItem *item = [[FSPlaylistItem alloc] init];
                                    item.title = url;
                                    item.url = [NSURL URLWithString:url];
                                    
                                    for (FSPlaylistItem *existingItem in self.userPlaylistItems) {
                                        if ([existingItem isEqual:item]) {
                                            return;
                                        }
                                    }
                                    
                                    [self.userPlaylistItems addObject:item];
                                    
                                    [self addUserPlaylistItems];
                                    [self.tableView reloadData];
                                }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)switchDiskCache:(id)sender
{
    NSString *message = nil;
    switch (self.diskCacheControl.selectedSegmentIndex) {
        case 0:
            message = @"Disk caching enabled.";
            _diskCachingAllowed = YES;
            break;
            
        case 1:
            message = @"Disk caching disabled.";
            _diskCachingAllowed = NO;
            break;
            
        default:
            break;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cache setting"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * action) {}]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)selectBufferSize:(id)sender
{
    UISegmentedControl *segmentedControl = sender;
    
    _configuration = [[FSStreamConfiguration alloc] init];
    
    switch ([segmentedControl selectedSegmentIndex]) {
        case 1:
            // 0 KB
            _configuration.usePrebufferSizeCalculationInSeconds = NO;
            _configuration.requiredInitialPrebufferedByteCountForContinuousStream = 0;
            _configuration.requiredInitialPrebufferedByteCountForNonContinuousStream = 0;
            break;
        case 2:
            // 100 KB
            _configuration.usePrebufferSizeCalculationInSeconds = NO;
            _configuration.requiredInitialPrebufferedByteCountForContinuousStream = 100000;
            _configuration.requiredInitialPrebufferedByteCountForNonContinuousStream = 100000;
            break;
        case 3:
            // 200 KB
            _configuration.usePrebufferSizeCalculationInSeconds = NO;
            _configuration.requiredInitialPrebufferedByteCountForContinuousStream = 200000;
            _configuration.requiredInitialPrebufferedByteCountForNonContinuousStream = 200000;
            break;
            
        default:
            // Use defaults
            _configuration.usePrebufferSizeCalculationInSeconds = YES;
            break;
    }
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
    
    _configuration.cacheEnabled = _diskCachingAllowed;

    self.playerViewController.configuration = _configuration;
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
