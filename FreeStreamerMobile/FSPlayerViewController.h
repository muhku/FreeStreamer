/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import <UIKit/UIKit.h>

@class FSPlaylistItem;
@class FSAudioController;

/**
 * The player view controller of the iOS example application.
 *
 * The view allows the user to control the player. See the
 * play:, pause: and seek: actions.
 */
@interface FSPlayerViewController : UIViewController {
    FSPlaylistItem *_selectedPlaylistItem;
    
    // State
    BOOL _paused;
    BOOL _shouldStartPlaying;
    
    // UI
    NSTimer *_progressUpdateTimer;
    NSTimer *_playbackSeekTimer;
    double _seekToPoint;
}

/**
 * If this property is set to true, the stream playback is started
 * when the view appears. When the playback starts, the property
 * is automatically set to false. For consequent playback requests,
 * the flag must be activated again.
 */
@property (nonatomic,assign) BOOL shouldStartPlaying;
/**
 * The current (active) playlist item for playback.
 */
@property (nonatomic,strong) FSPlaylistItem *selectedPlaylistItem;

/**
 * Reference to the play button.
 */
@property (nonatomic,strong) IBOutlet UIButton *playButton;
/**
 * Reference to the pause button.
 */
@property (nonatomic,strong) IBOutlet UIButton *pauseButton;
/**
 * Reference to the progress slider.
 */
@property (nonatomic,strong) IBOutlet UISlider *progressSlider;
/**
 * Reference to the activity indicator. When the stream is buffering,
 * displays to the user.
 */
@property (nonatomic,strong) IBOutlet UIActivityIndicatorView *activityIndicator;
/**
 * Reference to the status label.
 */
@property (nonatomic,strong) IBOutlet UILabel *statusLabel;
/**
 * Reference to the label displaying the current playback time.
 */
@property (nonatomic,strong) IBOutlet UILabel *currentPlaybackTime;
/**
 * Reference to the audio controller.
 */
@property (nonatomic,strong) IBOutlet FSAudioController *audioController;

/**
 * Handles the notification upon the audio stream state change.
 *
 * @param notification The audio stream state notification.
 */
- (void)audioStreamStateDidChange:(NSNotification *)notification;

/**
 * Handles remote control events.
 * @param receivedEvent The event received.
 */
- (void)remoteControlReceivedWithEvent:(UIEvent *)receivedEvent;
/**
 * An action for starting the playback of the stream.
 *
 * @param sender The sender of the action.
 */
- (IBAction)play:(id)sender;
/**
 * An action for pausing the stream.
 *
 * @param sender The sender of the action.
 */
- (IBAction)pause:(id)sender;
/**
 * An action for seeking the stream.
 *
 * @param sender The sender of the action.
 */
- (IBAction)seek:(id)sender;

@end