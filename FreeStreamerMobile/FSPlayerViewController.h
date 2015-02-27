/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2015 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <UIKit/UIKit.h>

#import "FSAudioController.h"

@class FSAudioStream;
@class FSPlaylistItem;
@class FSFrequencyDomainAnalyzer;
@class FSFrequencyPlotView;

/**
 * The player view controller of the iOS example application.
 *
 * The view allows the user to control the player. See the
 * play:, pause: and seek: actions.
 */
@interface FSPlayerViewController : UIViewController <FSAudioControllerDelegate> {
    FSPlaylistItem *_selectedPlaylistItem;
    
    // State
    BOOL _shouldStartPlaying;
    float _outputVolume;
    BOOL _analyzerEnabled;
    
    FSFrequencyDomainAnalyzer *_analyzer;
    
    FSAudioController *_controller;
    FSSeekByteOffset _lastSeekByteOffset;
    NSURL *_lastPlaybackURL;
    
    float _maxPrebufferedByteCount;
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
 * Reference to the next button.
 */
@property (nonatomic,strong) IBOutlet UIButton *nextButton;
/**
 * Reference to the previous button.
 */
@property (nonatomic,strong) IBOutlet UIButton *previousButton;
/**
 * Reference to the pause button.
 */
@property (nonatomic,strong) IBOutlet UIButton *analyzerButton;
/**
 * Reference to the progress slider.
 */
@property (nonatomic,strong) IBOutlet UISlider *progressSlider;
/**
 * Reference to the volume slider.
 */
@property (nonatomic,strong) IBOutlet UISlider *volumeSlider;
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
@property (nonatomic,strong) FSAudioController *audioController;
/**
 * Reference to the frequency plot.
 */
@property (nonatomic,strong) IBOutlet FSFrequencyPlotView *frequencyPlotView;
/**
 * Reference to the buffering indicator.
 */
@property (nonatomic,strong) IBOutlet UIProgressView *bufferingIndicator;
/**
 * Reference to the prebuffer status.
 */
@property (nonatomic,strong) IBOutlet UIView *prebufferStatus;
/**
 * Handles the notification upon entering background.
 *
 * @param notification The notification.
 */
- (void)applicationDidEnterBackgroundNotification:(NSNotification *)notification;
/**
 * Handles the notification upon entering foreground.
 *
 * @param notification The notification.
 */
- (void)applicationWillEnterForegroundNotification:(NSNotification *)notification;
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
 * An action for Playing the next item of a multi-item playlist.
 *
 * @param sender The sender of the action.
 */
-(IBAction)playNext:(id)sender;
/**
 * An action for Playing the previous item of a multi-item playlist.
 *
 * @param sender The sender of the action.
 */
-(IBAction)playPrevious:(id)sender;
/**
 * An action for seeking the stream.
 *
 * @param sender The sender of the action.
 */
- (IBAction)seek:(id)sender;
/**
 * An action for opening the station URL.
 *
 * @param sender The sender of the action.
 */
- (IBAction)openStationUrl:(id)sender;
/**
 * An action for changing the volume.
 *
 * @param sender The sender of the action.
 */
- (IBAction)changeVolume:(id)sender;
/**
 * An action for toggling the analyzer on/off.
 *
 * @param sender The sender of the action.
 */
- (IBAction)toggleAnalyzer:(id)sender;

@end