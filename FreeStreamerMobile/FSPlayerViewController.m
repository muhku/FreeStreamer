/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSPlayerViewController.h"

#import "FSAudioStream.h"
#import "FSAudioController.h"
#import "FSPlaylistItem.h"

@interface FSPlayerViewController (PrivateMethods)

- (void)updatePlaybackProgress;
- (void)seekToNewTime;

@end

@implementation FSPlayerViewController

@synthesize playButton;
@synthesize pauseButton;
@synthesize shouldStartPlaying=_shouldStartPlaying;
@synthesize progressSlider=_progressSlider;
@synthesize activityIndicator=_activityIndicator;
@synthesize statusLabel=_statusLabel;
@synthesize currentPlaybackTime=_currentPlaybackTime;
@synthesize audioController;

/*
 * =======================================
 * View control
 * =======================================
 */

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                animated:NO];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationController.navigationBarHidden = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    if (_shouldStartPlaying) {
        _shouldStartPlaying = NO;
        [self.audioController play];
    }
    
    _progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                            target:self
                                                          selector:@selector(updatePlaybackProgress)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)viewDidLoad {
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
    
    // Hide the buttons as we display them based on the playback status (callback)
    self.playButton.hidden = YES;
    self.pauseButton.hidden = YES;
}

- (void)viewDidUnload {
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    self.selectedPlaylistItem = nil;
    
    self.activityIndicator = nil;
    self.statusLabel = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    if (_progressUpdateTimer) {
        [_progressUpdateTimer invalidate], _progressUpdateTimer = nil;
    }
}

/*
 * =======================================
 * Observers
 * =======================================
 */

- (void)audioStreamStateDidChange:(NSNotification *)notification {
    NSString *statusRetrievingURL = @"Retrieving stream URL";
    NSString *statusBuffering = @"Buffering...";
    NSString *statusSeeking = @"Seeking...";
    NSString *statusEmpty = @"";
    
    NSDictionary *dict = [notification userInfo];
    int state = [[dict valueForKey:FSAudioStreamNotificationKey_State] intValue];
    
    switch (state) {
        case kFsAudioStreamRetrievingURL:
            [_activityIndicator startAnimating];
            self.statusLabel.text = statusRetrievingURL;
            [_statusLabel setHidden:NO];
            self.progressSlider.enabled = NO;
            self.playButton.hidden = YES;
            self.pauseButton.hidden = NO;
            _paused = NO;
            break;
            
        case kFsAudioStreamStopped:
            [_activityIndicator stopAnimating];
            self.statusLabel.text = statusEmpty;
            self.progressSlider.enabled = NO;
            self.playButton.hidden = NO;
            self.pauseButton.hidden = YES;
            _paused = NO;
            break;
            
        case kFsAudioStreamBuffering:
            self.statusLabel.text = statusBuffering;
            [_activityIndicator startAnimating];
            [_statusLabel setHidden:NO];
            self.progressSlider.enabled = NO;
            self.playButton.hidden = YES;
            self.pauseButton.hidden = NO;
            _paused = NO;
            break;
            
        case kFsAudioStreamSeeking:
            self.statusLabel.text = statusSeeking;
            [_activityIndicator startAnimating];
            [_statusLabel setHidden:NO];
            self.progressSlider.enabled = NO;
            self.playButton.hidden = YES;
            self.pauseButton.hidden = NO;
            _paused = NO;
            break;
            
        case kFsAudioStreamPlaying:
            [_activityIndicator stopAnimating];
            if ([self.statusLabel.text isEqualToString:statusBuffering] ||
                [self.statusLabel.text isEqualToString:statusRetrievingURL] ||
                [self.statusLabel.text isEqualToString:statusSeeking]) {
                self.statusLabel.text = statusEmpty;
            }
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
            [_activityIndicator stopAnimating];
            self.progressSlider.enabled = NO;
            self.playButton.hidden = NO;
            self.pauseButton.hidden = YES;
            _paused = NO;
            break;
    }
}

- (void)audioStreamErrorOccurred:(NSNotification *)notification {
    [_statusLabel setHidden:NO];
    
    NSDictionary *dict = [notification userInfo];
    int errorCode = [[dict valueForKey:FSAudioStreamNotificationKey_Error] intValue];
    
    switch (errorCode) {
        case kFsAudioStreamErrorOpen:
            self.statusLabel.text = @"Cannot open the audio stream";
            break;
        case kFsAudioStreamErrorStreamParse:
            self.statusLabel.text = @"Cannot read the audio stream";
            break;
        case kFsAudioStreamErrorNetwork:
            self.statusLabel.text = @"Network failed: cannot play the audio stream";
            break;
        default:
            self.statusLabel.text = @"Unknown error occurred";
            break;
    }
}

- (void)audioStreamMetaDataAvailable:(NSNotification *)notification {
    NSString *streamTitle = @"";
    
    NSDictionary *dict = [notification userInfo];
    
    NSString *metaData = [dict valueForKey:FSAudioStreamNotificationKey_MetaData];
    NSRange start = [metaData rangeOfString:@"StreamTitle='"];
    
    if (start.location == NSNotFound) {
        goto out;
    }
    
    streamTitle = [metaData substringFromIndex:start.location + 13];
    NSRange end = [streamTitle rangeOfString:@"';"];
    
    if (end.location == NSNotFound) {
        goto out;
    }
                   
    streamTitle = [streamTitle substringToIndex:end.location];
    
out:
    [_statusLabel setHidden:NO];
    self.statusLabel.text = streamTitle;
}

/*
 * =======================================
 * Stream control
 * =======================================
 */

- (IBAction)play:(id)sender {
    if (_paused) {
        [self.audioController pause];
        _paused = NO;
    } else {
        [self.audioController play];
    }
    
    self.playButton.hidden = YES;
    self.pauseButton.hidden = NO;
}

- (IBAction)pause:(id)sender {
    [self.audioController pause];
    
    _paused = YES;
    
    self.playButton.hidden = NO;
    self.pauseButton.hidden = YES;
}

- (IBAction)seek:(id)sender {
    _seekToPoint = self.progressSlider.value;
    
    [_progressUpdateTimer invalidate], _progressUpdateTimer = nil;
    
    [_playbackSeekTimer invalidate], _playbackSeekTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                                           target:self
                                                                                         selector:@selector(seekToNewTime)
                                                                                           userInfo:nil
                                                                                            repeats:NO];
}

/*
 * =======================================
 * Properties
 * =======================================
 */

- (void)setSelectedPlaylistItem:(FSPlaylistItem *)selectedPlaylistItem {
    if (_selectedPlaylistItem == selectedPlaylistItem) {
        return;
    }
    
    _selectedPlaylistItem = selectedPlaylistItem;
    
    self.navigationItem.title = self.selectedPlaylistItem.title;
    
    [self.audioController stop];
    
    self.audioController.url = self.selectedPlaylistItem.nsURL;
}

- (FSPlaylistItem *)selectedPlaylistItem {
    return _selectedPlaylistItem;
}

/*
 * =======================================
 * Private
 * =======================================
 */

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

@end
