/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSXPlayerViewController.h"
#import "FSAudioStream.h"

@interface FSXPlayerViewController ()

- (void)updatePlaybackProgress;

- (void)audioStreamStateDidChange:(NSNotification *)notification;
- (void)audioStreamErrorOccurred:(NSNotification *)notification;
- (void)audioStreamMetaDataAvailable:(NSNotification *)notification;

@end

@implementation FSXPlayerViewController

@synthesize urlTextField;
@synthesize stateTextFieldCell;
@synthesize progressTextFieldCell;

- (FSAudioController *)audioController
{
    if (!_audioController) {
        _audioController = [[FSAudioController alloc] init];
        
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
    }
    return _audioController;
}

- (IBAction)playFromUrl:(id)sender
{
    NSString *url = [self.urlTextField stringValue];
    
    if (![self.audioController.url isEqual:url]) {
        [self.audioController stop];
        
        self.audioController.url = url;
    }
    
    if (_paused) {
        [self.audioController pause];
        _paused = NO;
    } else {
        [self.audioController play];
    }
    
    [self.playButton setHidden:YES];
    [self.pauseButton setHidden:NO];
    
    [self.urlTextField setEditable:NO];
}

- (IBAction)pause:(id)sender
{
    [self.audioController pause];
    
    _paused = YES;
    
    [self.playButton setHidden:NO];
    [self.pauseButton setHidden:YES];
    
    [self.urlTextField setEditable:YES];
}

/*
 * =======================================
 * Private
 * =======================================
 */

- (void)updatePlaybackProgress
{
    if (self.audioController.stream.continuous) {
        [self.progressTextFieldCell setTitle:@""];
    } else {
        FSStreamPosition cur = self.audioController.stream.currentTimePlayed;
        FSStreamPosition end = self.audioController.stream.duration;
        
        [self.progressTextFieldCell setTitle:[NSString stringWithFormat:@"%i:%02i / %i:%02i",
                                         cur.minute, cur.second,
                                         end.minute, end.second]];
    }
}

/*
 * =======================================
 * Observers
 * =======================================
 */

- (void)audioStreamStateDidChange:(NSNotification *)notification
{
    NSString *statusRetrievingURL = @"Retrieving stream URL";
    NSString *statusBuffering = @"Buffering...";
    NSString *statusSeeking = @"Seeking...";
    NSString *statusEmpty = @"";
    
    NSDictionary *dict = [notification userInfo];
    int state = [[dict valueForKey:FSAudioStreamNotificationKey_State] intValue];
    
    switch (state) {
        case kFsAudioStreamRetrievingURL:
            [self.stateTextFieldCell setTitle:statusRetrievingURL];
            [self.urlTextField setEditable:NO];

            [self.playButton setHidden:YES];
            [self.pauseButton setHidden:NO];
            _paused = NO;
            
            if (_progressUpdateTimer) {
                [_progressUpdateTimer invalidate];
            }
            [self.progressTextFieldCell setTitle:@""];
            
            break;
            
        case kFsAudioStreamStopped:
            [self.stateTextFieldCell setTitle:statusEmpty];
            [self.urlTextField setEditable:YES];

            [self.playButton setHidden:NO];
            [self.pauseButton setHidden:YES];
            _paused = NO;
            
            if (_progressUpdateTimer) {
                [_progressUpdateTimer invalidate];
            }
            [self.progressTextFieldCell setTitle:@""];
            
            break;
            
        case kFsAudioStreamBuffering:
            [self.stateTextFieldCell setTitle:statusBuffering];
            [self.urlTextField setEditable:NO];
            
            [self.playButton setHidden:YES];
            [self.pauseButton setHidden:NO];
            _paused = NO;
            
            if (_progressUpdateTimer) {
                [_progressUpdateTimer invalidate];
            }
            [self.progressTextFieldCell setTitle:@""];
            
            break;
            
        case kFsAudioStreamSeeking:
            [self.stateTextFieldCell setTitle:statusSeeking];
            [self.urlTextField setEditable:NO];
            
            [self.playButton setHidden:YES];
            [self.pauseButton setHidden:NO];
            _paused = NO;
            break;
            
        case kFsAudioStreamPlaying:
            [self.urlTextField setEditable:NO];
            
            if ([[self.stateTextFieldCell title] isEqualToString:statusBuffering] ||
                [[self.stateTextFieldCell title] isEqualToString:statusRetrievingURL] ||
                [[self.stateTextFieldCell title] isEqualToString:statusSeeking]) {
                [self.stateTextFieldCell setTitle:statusEmpty];
            }
            
            [self.playButton setHidden:YES];
            [self.pauseButton setHidden:NO];
            _paused = NO;
            
            if (_progressUpdateTimer) {
                [_progressUpdateTimer invalidate];
            }
            
            _progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                    target:self
                                                                  selector:@selector(updatePlaybackProgress)
                                                                  userInfo:nil
                                                                   repeats:YES];
            
            break;
            
        case kFsAudioStreamFailed:
            [self.urlTextField setEditable:YES];
            
            [self.playButton setHidden:NO];
            [self.pauseButton setHidden:YES];
            _paused = NO;
            
            if (_progressUpdateTimer) {
                [_progressUpdateTimer invalidate];
            }
            
            break;
    }
}

- (void)audioStreamErrorOccurred:(NSNotification *)notification
{
    NSDictionary *dict = [notification userInfo];
    int errorCode = [[dict valueForKey:FSAudioStreamNotificationKey_Error] intValue];
    
    switch (errorCode) {
        case kFsAudioStreamErrorOpen:
            [self.stateTextFieldCell setTitle:@"Cannot open the audio stream"];
            break;
        case kFsAudioStreamErrorStreamParse:
            [self.stateTextFieldCell setTitle:@"Cannot read the audio stream"];
            break;
        case kFsAudioStreamErrorNetwork:
            [self.stateTextFieldCell setTitle:@"Network failed: cannot play the audio stream"];
            break;
        default:
            [self.stateTextFieldCell setTitle:@"Unknown error occurred"];
            break;
    }
}

- (void)audioStreamMetaDataAvailable:(NSNotification *)notification
{
    NSString *streamTitle = @"";
    
    NSDictionary *dict = [notification userInfo];
    
    NSString *metaData = [dict valueForKey:FSAudioStreamNotificationKey_MetaData];
    NSRange start = [metaData rangeOfString:@"StreamTitle='"];
    
    if (start.location == NSNotFound) {
        goto done;
    }
    
    streamTitle = [metaData substringFromIndex:start.location + 13];
    NSRange end = [streamTitle rangeOfString:@"';"];
    
    if (end.location == NSNotFound) {
        goto done;
    }
    
    streamTitle = [streamTitle substringToIndex:end.location];

done:
    [self.stateTextFieldCell setTitle:streamTitle];
}

@end
