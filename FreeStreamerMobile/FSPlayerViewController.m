/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2015 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSPlayerViewController.h"

#import <MediaPlayer/MediaPlayer.h>

#import "FSAudioStream.h"
#import "FSAudioController.h"
#import "FSPlaylistItem.h"
#import "FSFrequencyDomainAnalyzer.h"
#import "FSFrequencyPlotView.h"
#import "AJNotificationView.h"

/*
 * To pause after seeking, uncomment the following line:
 */
//#define PAUSE_AFTER_SEEKING 1

@interface FSPlayerViewController ()

@property (nonatomic,assign) BOOL paused;
@property (nonatomic,strong) NSTimer *progressUpdateTimer;
@property (nonatomic,assign) float volumeBeforeRamping;
@property (nonatomic,assign) int rampStep;
@property (nonatomic,assign) int rampStepCount;
@property (nonatomic,assign) bool rampUp;
@property (nonatomic,assign) SEL postRampAction;
@property (nonatomic,strong) NSTimer *playbackSeekTimer;
@property (nonatomic,strong) NSTimer *volumeRampTimer;
@property (nonatomic,assign) double seekToPoint;
@property (nonatomic,copy) NSURL *stationURL;
@property (nonatomic,strong) UIBarButtonItem *infoButton;

- (void)clearStatus;
- (void)showStatus:(NSString *)status;
- (void)showErrorStatus:(NSString *)status;
- (void)updatePlaybackProgress;
- (void)rampVolume;
- (void)seekToNewTime;
- (void)determineStationNameWithMetaData:(NSDictionary *)metaData;
- (void)doSeeking;
- (void)finalizeSeeking;

@end

@implementation FSPlayerViewController

/*
 * =======================================
 * View control
 * =======================================
 */

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 70000)
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent
                                                animated:NO];
#else
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                animated:NO];
#endif
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBarHidden = NO;
    
    self.nextButton.hidden = YES;
    self.previousButton.hidden = YES;
    
    self.stationURL = nil;
    self.navigationItem.rightBarButtonItem = nil;
    
    self.view.backgroundColor = [UIColor clearColor];
    
    self.bufferingIndicator.hidden = YES;
    self.prebufferStatus.hidden = YES;
    
    [self.audioController setVolume:_outputVolume];
    self.volumeSlider.value = _outputVolume;
    
    _maxPrebufferedByteCount = (float)self.audioController.activeStream.configuration.maxPrebufferedByteCount;
    
    __weak FSPlayerViewController *weakSelf = self;
    
    self.audioController.onStateChange = ^(FSAudioStreamState state) {
        switch (state) {
            case kFsAudioStreamRetrievingURL:
                [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
                
                [weakSelf showStatus:@"Retrieving URL..."];
                
                weakSelf.statusLabel.text = @"";
                
                weakSelf.progressSlider.enabled = NO;
                weakSelf.playButton.hidden = YES;
                weakSelf.pauseButton.hidden = NO;
                weakSelf.paused = NO;
                break;
                
            case kFsAudioStreamStopped:
                [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                
                weakSelf.statusLabel.text = @"";
                
                weakSelf.progressSlider.enabled = NO;
                weakSelf.playButton.hidden = NO;
                weakSelf.pauseButton.hidden = YES;
                weakSelf.paused = NO;
                break;
                
            case kFsAudioStreamBuffering:
                [weakSelf showStatus:@"Buffering..."];
                
                [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
                weakSelf.progressSlider.enabled = NO;
                weakSelf.playButton.hidden = YES;
                weakSelf.pauseButton.hidden = NO;
                weakSelf.paused = NO;
                break;
                
            case kFsAudioStreamSeeking:
                [weakSelf showStatus:@"Seeking..."];
                
                [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
                weakSelf.progressSlider.enabled = NO;
                weakSelf.playButton.hidden = YES;
                weakSelf.pauseButton.hidden = NO;
                weakSelf.paused = NO;
                break;
                
            case kFsAudioStreamPlaying:
                [weakSelf determineStationNameWithMetaData:nil];
                
                [weakSelf clearStatus];
                
                [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                
                weakSelf.progressSlider.enabled = YES;
                
                if (!weakSelf.progressUpdateTimer) {
                    weakSelf.progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                            target:weakSelf
                                                                          selector:@selector(updatePlaybackProgress)
                                                                          userInfo:nil
                                                                           repeats:YES];
                }
                
                if (weakSelf.volumeBeforeRamping > 0) {
                    // If we have volume before ramping set, it means we were seeked
                    
#if PAUSE_AFTER_SEEKING
                    [weakSelf pause:weakSelf];
                    weakSelf.audioController.volume = weakSelf.volumeBeforeRamping;
                    weakSelf.volumeBeforeRamping = 0;
                    
                    break;
#else
                    weakSelf.rampStep = 1;
                    weakSelf.rampStepCount = 5; // 50ms and 5 steps = 250ms ramp
                    weakSelf.rampUp = true;
                    weakSelf.postRampAction = @selector(finalizeSeeking);
                    
                    weakSelf.volumeRampTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 // 50ms
                                                                        target:weakSelf
                                                                      selector:@selector(rampVolume)
                                                                      userInfo:nil
                                                                       repeats:YES];
#endif
                }
                [weakSelf toggleNextPreviousButtons];
                weakSelf.playButton.hidden = YES;
                weakSelf.pauseButton.hidden = NO;
                weakSelf.paused = NO;
                
                break;
                
            case kFsAudioStreamFailed:
                [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                weakSelf.progressSlider.enabled = NO;
                weakSelf.playButton.hidden = NO;
                weakSelf.pauseButton.hidden = YES;
                weakSelf.paused = NO;
                break;
            case kFsAudioStreamPlaybackCompleted:
                [weakSelf toggleNextPreviousButtons];
                break;
            
            case kFsAudioStreamRetryingStarted:
                [weakSelf showStatus:@"Attempt to retry playback..."];
                break;
                
            case kFsAudioStreamRetryingSucceeded:
                break;
                
            case kFsAudioStreamRetryingFailed:
                [weakSelf showErrorStatus:@"Failed to retry playback"];
                break;

            default:
                break;
        }
    };
    
    self.audioController.onFailure = ^(FSAudioStreamError error, NSString *errorDescription) {
        NSString *errorCategory;
        
        switch (error) {
            case kFsAudioStreamErrorOpen:
                errorCategory = @"Cannot open the audio stream: ";
                break;
            case kFsAudioStreamErrorStreamParse:
                errorCategory = @"Cannot read the audio stream: ";
                break;
            case kFsAudioStreamErrorNetwork:
                errorCategory = @"Network failed: cannot play the audio stream: ";
                break;
            case kFsAudioStreamErrorUnsupportedFormat:
                errorCategory = @"Unsupported format: ";
                break;
            case kFsAudioStreamErrorStreamBouncing:
                errorCategory = @"Network failed: cannot get enough data to play: ";
                break;
            default:
                errorCategory = @"Unknown error occurred: ";
                break;
        }
        
        NSString *formattedError = [NSString stringWithFormat:@"%@ %@", errorCategory, errorDescription];
        
        [weakSelf showErrorStatus:formattedError];
    };
    
    self.audioController.onMetaDataAvailable = ^(NSDictionary *metaData) {
        NSMutableString *streamInfo = [[NSMutableString alloc] init];
        
        [weakSelf determineStationNameWithMetaData:metaData];
        
        NSMutableDictionary *songInfo = [[NSMutableDictionary alloc] init];
        
        if (metaData[@"MPMediaItemPropertyTitle"]) {
            songInfo[MPMediaItemPropertyTitle] = metaData[@"MPMediaItemPropertyTitle"];
        } else if (metaData[@"StreamTitle"]) {
            songInfo[MPMediaItemPropertyTitle] = metaData[@"StreamTitle"];
        }
        
        if (metaData[@"MPMediaItemPropertyArtist"]) {
            songInfo[MPMediaItemPropertyArtist] = metaData[@"MPMediaItemPropertyArtist"];
        }
        
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:songInfo];
        
        if (metaData[@"MPMediaItemPropertyArtist"] &&
            metaData[@"MPMediaItemPropertyTitle"]) {
            [streamInfo appendString:metaData[@"MPMediaItemPropertyArtist"]];
            [streamInfo appendString:@" - "];
            [streamInfo appendString:metaData[@"MPMediaItemPropertyTitle"]];
        } else if (metaData[@"StreamTitle"]) {
            [streamInfo appendString:metaData[@"StreamTitle"]];
        }
        
        if (metaData[@"StreamUrl"] && [metaData[@"StreamUrl"] length] > 0) {
            weakSelf.stationURL = [NSURL URLWithString:metaData[@"StreamUrl"]];
            
            weakSelf.navigationItem.rightBarButtonItem = weakSelf.infoButton;
        }
        
        [weakSelf.statusLabel setHidden:NO];
        weakSelf.statusLabel.text = streamInfo;
    };
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (_shouldStartPlaying) {
        _shouldStartPlaying = NO;
        
        if ([self.audioController.url isEqual:_lastPlaybackURL]) {
            // The same file was playing from a position, resume
            [self.audioController.activeStream playFromOffset:_lastSeekByteOffset];
        } else {
            [self.audioController play];
        }
    }
    
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    [self becomeFirstResponder];
    
    _progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                            target:self
                                                          selector:@selector(updatePlaybackProgress)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackgroundNotification:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForegroundNotification:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    // Hide the buttons as we display them based on the playback status (callback)
    self.playButton.hidden = YES;
    self.pauseButton.hidden = YES;
    
    _infoButton = self.navigationItem.rightBarButtonItem;
    
    _outputVolume = 0.5;
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    
    [self resignFirstResponder];
    
    if (!self.audioController.activeStream.continuous && self.audioController.isPlaying) {
        // If a file with a duration is playing, store its last known playback position
        // so that we can resume from the same position, if the same file
        // is played again
        
        _lastSeekByteOffset = self.audioController.activeStream.currentSeekByteOffset;
        _lastPlaybackURL = [self.audioController.url copy];
    } else {
        _lastPlaybackURL = nil;
    }
    
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    // Free the resources (audio queue, etc.)
    _audioController = nil;
    
    if (_analyzerEnabled) {
        [self toggleAnalyzer:self];
    }
    
    if (_progressUpdateTimer) {
        [_progressUpdateTimer invalidate], _progressUpdateTimer = nil;
    }
}

/*
 * =======================================
 * Observers
 * =======================================
 */

- (void)remoteControlReceivedWithEvent:(UIEvent *)receivedEvent
{
    if (receivedEvent.type == UIEventTypeRemoteControl) {
        switch (receivedEvent.subtype) {
            case UIEventSubtypeRemoteControlPause: /* FALLTHROUGH */
            case UIEventSubtypeRemoteControlPlay:  /* FALLTHROUGH */
            case UIEventSubtypeRemoteControlTogglePlayPause:
                if (self.paused) {
                    [self play:self];
                } else {
                    [self pause:self];
                }
                break;
            default:
                break;
        }
    }
}

- (void)applicationDidEnterBackgroundNotification:(NSNotification *)notification
{
    _analyzer.enabled = NO;
    
    if (self.paused && self.audioController.activeStream.continuous) {
        // Don't leave paused continuous stream on background;
        // Stream will eventually fail and restart
        [self.audioController stop];
    }
}

- (void)applicationWillEnterForegroundNotification:(NSNotification *)notification
{
    _analyzer.enabled = _analyzerEnabled;
}

/*
 * =======================================
 * Stream control
 * =======================================
 */

- (IBAction)play:(id)sender
{
    if (self.paused) {
        /*
         * If we are paused, call pause again to unpause so
         * that the stream playback will continue.
         */
        [self.audioController pause];
        self.paused = NO;
    } else {
        /*
         * Not paused, just directly call play.
         */
        [self.audioController play];
    }
    
    self.playButton.hidden = YES;
    self.pauseButton.hidden = NO;
}

- (IBAction)pause:(id)sender
{
    [self.audioController pause];
    
    self.paused = YES;
    
    self.playButton.hidden = NO;
    self.pauseButton.hidden = YES;
}

- (IBAction)seek:(id)sender
{
    _seekToPoint = self.progressSlider.value;
    
    [_progressUpdateTimer invalidate], _progressUpdateTimer = nil;
    
    [_playbackSeekTimer invalidate], _playbackSeekTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                                           target:self
                                                                                         selector:@selector(seekToNewTime)
                                                                                           userInfo:nil
                                                                                            repeats:NO];
}

- (IBAction)openStationUrl:(id)sender
{
    [[UIApplication sharedApplication] openURL:_stationURL];
}

- (IBAction)changeVolume:(id)sender
{
    self.audioController.volume = self.volumeSlider.value;
}

-(IBAction)playNext:(id)sender
{
    [self.audioController playNextItem];
}

-(IBAction)playPrevious:(id)sender
{
    [self.audioController playPreviousItem];
}

-(void)toggleNextPreviousButtons
{
    if([self.audioController hasNextItem] || [self.audioController hasPreviousItem])
    {
        self.nextButton.hidden = NO;
        self.previousButton.hidden = NO;
        self.nextButton.enabled = [self.audioController hasNextItem];
        self.previousButton.enabled = [self.audioController hasPreviousItem];
    }
    else
    {
        self.nextButton.hidden = YES;
        self.previousButton.hidden = YES;
    }
}

- (IBAction)toggleAnalyzer:(id)sender
{
    if (!_analyzerEnabled) {
        _analyzer = [[FSFrequencyDomainAnalyzer alloc] init];
        _analyzer.delegate = self.frequencyPlotView;
        _analyzer.enabled = YES;
        
        self.frequencyPlotView.hidden = NO;
        _audioController.activeStream.delegate = _analyzer;
    } else {
        _audioController.activeStream.delegate = nil;
        
        [self.frequencyPlotView reset];
        self.frequencyPlotView.hidden = YES;
        
        _analyzer.shouldExit = YES;
        _analyzer = nil;
    }
    
    _analyzerEnabled = (!_analyzerEnabled);
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (void)setSelectedPlaylistItem:(FSPlaylistItem *)selectedPlaylistItem
{
    _selectedPlaylistItem = selectedPlaylistItem;
    
    self.navigationItem.title = self.selectedPlaylistItem.title;
    
    if (self.selectedPlaylistItem.url) {
        self.audioController.url =  self.selectedPlaylistItem.url;
    } else if (self.selectedPlaylistItem.originatingUrl) {
        self.audioController.url = self.selectedPlaylistItem.originatingUrl;
    }
}

- (FSPlaylistItem *)selectedPlaylistItem
{
    return _selectedPlaylistItem;
}

- (FSAudioController *)audioController
{
    if (!_audioController) {
        _audioController = [[FSAudioController alloc] init];
        _audioController.delegate = self;
    }
    return _audioController;
}

/*
 * =======================================
 * Delegates
 * =======================================
 */
- (void)audioController:(FSAudioController *)audioController preloadStartedForStream:(FSAudioStream *)stream
{
    // Should we display the preloading status somehow?
}

/*
 * =======================================
 * Private
 * =======================================
 */

- (void)clearStatus
{
    [AJNotificationView hideCurrentNotificationViewAndClearQueue];
}

- (void)showStatus:(NSString *)status
{
    [self clearStatus];
    
    [AJNotificationView showNoticeInView:[[[UIApplication sharedApplication] delegate] window]
                                    type:AJNotificationTypeDefault
                                   title:status
                         linedBackground:AJLinedBackgroundTypeAnimated
                               hideAfter:0];
}

- (void)showErrorStatus:(NSString *)status
{
    [self clearStatus];
    
    [AJNotificationView showNoticeInView:[[[UIApplication sharedApplication] delegate] window]
                                    type:AJNotificationTypeRed
                                   title:status
                               hideAfter:10];
}

- (void)updatePlaybackProgress
{
    if (self.audioController.activeStream.continuous) {
        self.progressSlider.enabled = NO;
        self.progressSlider.value = 0;
        self.currentPlaybackTime.text = @"";
    } else {
        self.progressSlider.enabled = YES;
        
        FSStreamPosition cur = self.audioController.activeStream.currentTimePlayed;
        FSStreamPosition end = self.audioController.activeStream.duration;
        
        self.progressSlider.value = cur.position;
        
        self.currentPlaybackTime.text = [NSString stringWithFormat:@"%i:%02i / %i:%02i",
                                         cur.minute, cur.second,
                                         end.minute, end.second];
    }
    
    self.bufferingIndicator.hidden = NO;
    self.prebufferStatus.hidden = YES;
    
    if (self.audioController.activeStream.contentLength > 0) {
        // A non-continuous stream, show the buffering progress within the whole file
        FSSeekByteOffset currentOffset = self.audioController.activeStream.currentSeekByteOffset;
        
        UInt64 totalBufferedData = currentOffset.start + self.audioController.activeStream.prebufferedByteCount;
        
        float bufferedDataFromTotal = (float)totalBufferedData / self.audioController.activeStream.contentLength;
        
        self.bufferingIndicator.progress = (float)currentOffset.start / self.audioController.activeStream.contentLength;
        
        // Use the status to show how much data we have in the buffers
        self.prebufferStatus.frame = CGRectMake(self.bufferingIndicator.frame.origin.x,
                                                self.bufferingIndicator.frame.origin.y,
                                                CGRectGetWidth(self.bufferingIndicator.frame) * bufferedDataFromTotal,
                                                5);
        self.prebufferStatus.hidden = NO;
    } else {
        // A continuous stream, use the buffering indicator to show progress
        // among the filled prebuffer
        self.bufferingIndicator.progress = (float)self.audioController.activeStream.prebufferedByteCount / _maxPrebufferedByteCount;
    }
}

- (void)rampVolume
{
    if (_rampStep > _rampStepCount) {
        [_volumeRampTimer invalidate], _volumeRampTimer = nil;
        
        if (_postRampAction) {
            [self performSelector:_postRampAction withObject:nil afterDelay:0];
        }
        
        return;
    }
    
    if (_rampUp) {
        self.audioController.volume = (_volumeBeforeRamping / _rampStepCount) * _rampStep;
    } else {
        self.audioController.volume = (_volumeBeforeRamping / _rampStepCount) * (_rampStepCount - _rampStep);
    }
    
    _rampStep++;
}

- (void)seekToNewTime
{
    self.progressSlider.enabled = NO;
    
    // Fade out the volume to avoid pops
    _volumeBeforeRamping = self.audioController.volume;
    
    if (_volumeBeforeRamping > 0) {
        _rampStep = 1;
        _rampStepCount = 5; // 50ms and 5 steps = 250ms ramp
        _rampUp = false;
        _postRampAction = @selector(doSeeking);
        
        _volumeRampTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 // 50ms
                                                            target:self
                                                          selector:@selector(rampVolume)
                                                          userInfo:nil
                                                           repeats:YES];
    } else {
        // Just directly seek, volume is already 0
        [self doSeeking];
    }
}

- (void)determineStationNameWithMetaData:(NSDictionary *)metaData
{
    if (metaData[@"IcecastStationName"] && [metaData[@"IcecastStationName"] length] > 0) {
        self.navigationController.navigationBar.topItem.title = metaData[@"IcecastStationName"];
    } else {
        FSPlaylistItem *playlistItem = self.audioController.currentPlaylistItem;
        NSString *title = playlistItem.title;
        
        if ([playlistItem.title length] > 0) {
            self.navigationController.navigationBar.topItem.title = title;
        } else {
            /* The last resort - use the URL as the title, if available */
            if (metaData[@"StreamUrl"] && [metaData[@"StreamUrl"] length] > 0) {
                self.navigationController.navigationBar.topItem.title = metaData[@"StreamUrl"];
            }
        }
    }
}

- (void)doSeeking
{
    FSStreamPosition pos = {0};
    pos.position = _seekToPoint;
    
    [self.audioController.activeStream seekToPosition:pos];
}

- (void)finalizeSeeking
{
    _volumeBeforeRamping = 0;
}

@end