/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <UIKit/UIKit.h>

@class FSPlaylistItem;

@interface FSPlayerViewController : UIViewController {
    FSPlaylistItem *_selectedPlaylistItem;
    BOOL _shouldStartPlaying;
    
    // UI
    UIActivityIndicatorView *_activityIndicator;
    UILabel *_statusLabel;
}

@property (nonatomic,assign) BOOL shouldStartPlaying;
@property (nonatomic,strong) FSPlaylistItem *selectedPlaylistItem;

@property (nonatomic,strong) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (nonatomic,strong) IBOutlet UILabel *statusLabel;

- (void)audioStreamStateDidChange:(NSNotification *)notification;  
- (IBAction)play:(id)sender;
- (IBAction)stop:(id)sender;

@end
