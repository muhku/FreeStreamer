/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <UIKit/UIKit.h>

@class FSPlaylistItem;
@class FSAudioController;

@interface FSPlayerViewController : UIViewController {
    FSPlaylistItem *_selectedPlaylistItem;
    BOOL _shouldStartPlaying;
    
    // UI
    UISlider *_progressSlider;
    NSTimer *_progressUpdateTimer;
    UIActivityIndicatorView *_activityIndicator;
    UILabel *_statusLabel;
    UILabel *_currentPlaybackTime;
    NSTimer *_playbackSeekTimer;
    double _seekToPoint;
}

@property (nonatomic,assign) BOOL shouldStartPlaying;
@property (nonatomic,strong) FSPlaylistItem *selectedPlaylistItem;

@property (nonatomic,strong) IBOutlet UISlider *progressSlider;
@property (nonatomic,strong) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (nonatomic,strong) IBOutlet UILabel *statusLabel;
@property (nonatomic,strong) IBOutlet UILabel *currentPlaybackTime;

@property (nonatomic,strong) IBOutlet FSAudioController *audioController;

- (void)audioStreamStateDidChange:(NSNotification *)notification;  
- (IBAction)play:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)seek:(id)sender;

@end
