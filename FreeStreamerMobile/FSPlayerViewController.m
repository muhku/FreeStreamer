/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSPlayerViewController.h"

#import "FSAudioStream.h"
#import "FSAudioController.h"
#import "FSPlaylistItem.h"
#import "FSFrequencyDomainAnalyzer.h"
#import "FSFrequencyPlotView.h"
#import "AJNotificationView.h"

/*
 * Comment the following line, if you want to disable the frequency analyzer.
 *
 * Do not unnecessarily enable the analyzer, as it will consume considerable
 * amount of CPU, thus, battery. It is enabled by default as a sake of
 * demonstration.
 */
#define ENABLE_ANALYZER 1

@interface FSPlayerViewController ()

- (void)clearStatus;
- (void)showStatus:(NSString *)status;
- (void)showErrorStatus:(NSString *)status;
- (void)updatePlaybackProgress;
- (void)seekToNewTime;
- (void)determineStationNameWithMetaData:(NSDictionary *)metaData;

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
    
    _stationURL = nil;
    self.navigationItem.rightBarButtonItem = nil;
    
    self.view.backgroundColor = [UIColor clearColor];
    
    self.bufferingIndicator.hidden = YES;
    
    [self.audioController setVolume:_outputVolume];
    self.volumeSlider.value = _outputVolume;
    
#if ENABLE_ANALYZER
    self.analyzer.enabled = YES;
#else
    self.frequencyPlotView.hidden = YES;
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    if (_shouldStartPlaying) {
        _shouldStartPlaying = NO;
        
        if ([self.audioController.url isEqual:_lastPlaybackURL]) {
            // The same file was playing from a position, resume
            [self.audioController.stream playFromOffset:_lastSeekByteOffset];
        } else {
            [self.audioController play];
        }
    }
    
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    [self becomeFirstResponder];
    
    _progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                            target:self
                                                          selector:@selector(updatePlaybackProgress)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioStreamStateDidChange:)
                                                 name:FSAudioStreamStateChangeNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioStreamErrorOccurred:)
                                                 name:FSAudioStreamErrorNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioStreamMetaDataAvailable:)
                                                 name:FSAudioStreamMetaDataNotification
                                               object:nil];
    
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
    
#if ENABLE_ANALYZER
    self.analyzer = [[FSFrequencyDomainAnalyzer alloc] init];
    self.analyzer.delegate = self.frequencyPlotView;
#endif
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
    
    if (!self.audioController.stream.continuous && self.audioController.isPlaying) {
        // If a file with a duration is playing, store its last known playback position
        // so that we can resume from the same position, if the same file
        // is played again
        
        _lastSeekByteOffset = self.audioController.stream.currentSeekByteOffset;
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
    
#if ENABLE_ANALYZER
    self.analyzer.enabled = NO;
    [self.frequencyPlotView reset];
#endif
    
    if (_progressUpdateTimer) {
        [_progressUpdateTimer invalidate], _progressUpdateTimer = nil;
    }
}

/*
 * =======================================
 * Observers
 * =======================================
 */

- (void)audioStreamStateDidChange:(NSNotification *)notification
{
    NSDictionary *dict = [notification userInfo];
    int state = [[dict valueForKey:FSAudioStreamNotificationKey_State] intValue];
    
    switch (state) {
        case kFsAudioStreamRetrievingURL:
            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
            
            [self showStatus:@"Retrieving URL..."];
            
            self.statusLabel.text = @"";
            
            self.progressSlider.enabled = NO;
            self.playButton.hidden = YES;
            self.pauseButton.hidden = NO;
            _paused = NO;
            break;
            
        case kFsAudioStreamStopped:
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
            
            self.statusLabel.text = @"";
            
            self.progressSlider.enabled = NO;
            self.playButton.hidden = NO;
            self.pauseButton.hidden = YES;
            _paused = NO;
            break;
            
        case kFsAudioStreamBuffering:
            [self showStatus:@"Buffering..."];

            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
            self.progressSlider.enabled = NO;
            self.playButton.hidden = YES;
            self.pauseButton.hidden = NO;
            _paused = NO;
            break;
            
        case kFsAudioStreamSeeking:
            [self showStatus:@"Seeking..."];
            
            [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
            self.progressSlider.enabled = NO;
            self.playButton.hidden = YES;
            self.pauseButton.hidden = NO;
            _paused = NO;
            break;
            
        case kFsAudioStreamPlaying:
            [self determineStationNameWithMetaData:nil];
            
            [self clearStatus];
            
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
            
            self.progressSlider.enabled = YES;
            
            if (!_progressUpdateTimer) {
                _progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                        target:self
                                                                      selector:@selector(updatePlaybackProgress)
                                                                      userInfo:nil
                                                                       repeats:YES];
            }
            
            self.playButton.hidden = YES;
            self.pauseButton.hidden = NO;
            _paused = NO;
            
            break;
            
        case kFsAudioStreamFailed:
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
            self.progressSlider.enabled = NO;
            self.playButton.hidden = NO;
            self.pauseButton.hidden = YES;
            _paused = NO;
            break;
    }
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)receivedEvent
{
    if (receivedEvent.type == UIEventTypeRemoteControl) {
        switch (receivedEvent.subtype) {
            case UIEventSubtypeRemoteControlPause: /* FALLTHROUGH */
            case UIEventSubtypeRemoteControlPlay:  /* FALLTHROUGH */
            case UIEventSubtypeRemoteControlTogglePlayPause:
                if (_paused) {
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
#if ENABLE_ANALYZER
    self.analyzer.enabled = NO;
#endif
}

- (void)applicationWillEnterForegroundNotification:(NSNotification *)notification
{
#if ENABLE_ANALYZER
    self.analyzer.enabled = YES;
#endif
}

- (void)audioStreamErrorOccurred:(NSNotification *)notification
{
    NSDictionary *dict = [notification userInfo];
    int errorCode = [[dict valueForKey:FSAudioStreamNotificationKey_Error] intValue];
    
    NSString *errorDescription;
    
    switch (errorCode) {
        case kFsAudioStreamErrorOpen:
            errorDescription = @"Cannot open the audio stream";
            break;
        case kFsAudioStreamErrorStreamParse:
            errorDescription = @"Cannot read the audio stream";
            break;
        case kFsAudioStreamErrorNetwork:
            errorDescription = @"Network failed: cannot play the audio stream";
            break;
        case kFsAudioStreamErrorUnsupportedFormat:
            errorDescription = @"Unsupported format";
            break;
        case kFsAudioStreamErrorStreamBouncing:
            errorDescription = @"Network failed: cannot get enough data to play";
            break;
        default:
            errorDescription = @"Unknown error occurred";
            break;
    }
    
    [self showErrorStatus:errorDescription];
}

- (void)audioStreamMetaDataAvailable:(NSNotification *)notification
{
    NSDictionary *dict = [notification userInfo];
    NSDictionary *metaData = [dict valueForKey:FSAudioStreamNotificationKey_MetaData];
    
    NSMutableString *streamInfo = [[NSMutableString alloc] init];
    
    [self determineStationNameWithMetaData:metaData];
    
    if (metaData[@"MPMediaItemPropertyArtist"] &&
        metaData[@"MPMediaItemPropertyTitle"]) {
        [streamInfo appendString:metaData[@"MPMediaItemPropertyArtist"]];
        [streamInfo appendString:@" - "];
        [streamInfo appendString:metaData[@"MPMediaItemPropertyTitle"]];
    } else if (metaData[@"StreamTitle"]) {
        [streamInfo appendString:metaData[@"StreamTitle"]];
    }
    
    if (metaData[@"StreamUrl"] && [metaData[@"StreamUrl"] length] > 0) {
        _stationURL = [NSURL URLWithString:metaData[@"StreamUrl"]];
        
        self.navigationItem.rightBarButtonItem = _infoButton;
    }
    
    [_statusLabel setHidden:NO];
    self.statusLabel.text = streamInfo;
}

/*
 * =======================================
 * Stream control
 * =======================================
 */

- (IBAction)play:(id)sender
{
    if (_paused) {
        /*
         * If we are paused, call pause again to unpause so
         * that the stream playback will continue.
         */
        [self.audioController pause];
        _paused = NO;
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
    
    _paused = YES;
    
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
    _outputVolume =  self.volumeSlider.value;
    
    [self.audioController setVolume:_outputVolume];
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
    
    self.audioController.url = self.selectedPlaylistItem.nsURL;
}

- (FSPlaylistItem *)selectedPlaylistItem
{
    return _selectedPlaylistItem;
}

- (FSAudioController *)audioController
{
    if (!_audioController) {
        _audioController = [[FSAudioController alloc] init];
        
#if ENABLE_ANALYZER
        _audioController.stream.delegate = self.analyzer;
#endif
    }
    return _audioController;
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
    if (self.audioController.stream.continuous) {
        self.progressSlider.enabled = NO;
        self.progressSlider.value = 0;
        self.currentPlaybackTime.text = @"";
    } else {
        double s = self.audioController.stream.currentTimePlayed.minute * 60 + self.audioController.stream.currentTimePlayed.second;
        double e = self.audioController.stream.duration.minute * 60 + self.audioController.stream.duration.second;
        
        self.progressSlider.enabled = YES;
        self.progressSlider.value = s / e;
        
        FSStreamPosition cur = self.audioController.stream.currentTimePlayed;
        FSStreamPosition end = self.audioController.stream.duration;
        
        self.currentPlaybackTime.text = [NSString stringWithFormat:@"%i:%02i / %i:%02i",
                                         cur.minute, cur.second,
                                         end.minute, end.second];
    }
    
    self.bufferingIndicator.hidden = NO;
    
    self.bufferingIndicator.progress = (float)self.audioController.stream.prebufferedByteCount / (float)self.audioController.stream.configuration.maxPrebufferedByteCount;
}

- (void)seekToNewTime
{
    self.progressSlider.enabled = NO;
    
    unsigned u = (self.audioController.stream.duration.minute * 60 + self.audioController.stream.duration.second) * _seekToPoint;
    
    unsigned s,m;
    
    s = u % 60, u /= 60;
    m = u;
    
    FSStreamPosition pos;
    pos.minute = m;
    pos.second = s;
    
    [self.audioController.stream seekToPosition:pos];
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

@end