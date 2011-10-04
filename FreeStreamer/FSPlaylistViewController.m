/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSPlaylistViewController.h"
#import "FSAppDelegate.h"
#import "FSDAO.h"
#import "FSPlaylistItem.h"
#import "FSPlayerViewController.h"

@implementation FSPlaylistViewController

@synthesize navigationController=_navigationController;
@synthesize playerViewController=_playerViewContoller;

/*
 * =======================================
 * View controller
 * =======================================
 */

- (void)viewDidUnload {
    [super viewDidUnload];
    
    self.navigationController = nil;
    self.playerViewController = nil;
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
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
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
 * Properties
 * =======================================
 */

- (NSMutableArray *)playlistItems {
    FSAppDelegate *delegate = [[UIApplication sharedApplication] delegate];
    
    if (!_playlistItems) {
        _playlistItems = [[delegate.dao playlistItems] retain];
    }
    return _playlistItems;
}

@end
