/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSXPlayerViewController.h"

@interface FSXPlayerViewController ()

- (void)updatePlaybackProgress;

- (void)audioStreamStateDidChange:(NSNotification *)notification;
- (void)audioStreamErrorOccurred:(NSNotification *)notification;
- (void)audioStreamMetaDataAvailable:(NSNotification *)notification;

@end

@implementation FSXPlayerViewController

- (FSAudioController *)audioController
{
    if (!_audioController) {
        _audioController = [[FSAudioController alloc] init];
        _record = NO;
        
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
        
        self.audioController.url = [NSURL URLWithString:url];
    }
    
    if (_paused) {
        /*
         * If we are paused, call pause again to unpause so
         * that the stream playback will continue.
         */
        [self.audioController pause];
        _paused = NO;
    }
    
    [self.audioController play];
    
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

- (IBAction)record:(id)sender
{
    _record = (!_record);
    
    if (!_record) {
        self.audioController.activeStream.outputFile = nil;
        return;
    }
    
    NSMutableString *basePath = [[NSMutableString alloc] init];
    
    [basePath appendString:NSHomeDirectory()];
    [basePath appendString:@"/Desktop"];
    [basePath appendString:@"/FreeStreamer-capture"];
    
    NSString *fileName;
    unsigned index = 0;
    
    do {
        fileName = [[NSString alloc] initWithFormat:@"%@-%i.%@", basePath, index, self.audioController.activeStream.suggestedFileExtension];
        index++;
    } while ([[NSFileManager defaultManager] fileExistsAtPath:fileName]);
    
    self.audioController.activeStream.outputFile = [NSURL fileURLWithPath:fileName];
}

/*
 * =======================================
 * Private
 * =======================================
 */

- (void)updatePlaybackProgress
{
    if (self.audioController.activeStream.continuous) {
        [self.progressTextFieldCell setTitle:@""];
    } else {
        FSStreamPosition cur = self.audioController.activeStream.currentTimePlayed;
        FSStreamPosition end = self.audioController.activeStream.duration;
        
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
    if (!(notification.object == self.audioController.activeStream)) {
        return;
    }
    
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
    if (!(notification.object == self.audioController.activeStream)) {
        return;
    }
    
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
        case kFsAudioStreamErrorUnsupportedFormat:
            [self.stateTextFieldCell setTitle:@"Unsupported format"];
            break;
        case kFsAudioStreamErrorStreamBouncing:
            [self.stateTextFieldCell setTitle:@"Network failed: cannot get enough data to play"];
            break;
        default:
            [self.stateTextFieldCell setTitle:@"Unknown error occurred"];
            break;
    }
}

- (void)audioStreamMetaDataAvailable:(NSNotification *)notification
{
    if (!(notification.object == self.audioController.activeStream)) {
        return;
    }
    
    NSDictionary *dict = [notification userInfo];
    NSDictionary *metaData = [dict valueForKey:FSAudioStreamNotificationKey_MetaData];
    
    NSMutableString *streamInfo = [[NSMutableString alloc] init];
    
    if (metaData[@"MPMediaItemPropertyArtist"] &&
        metaData[@"MPMediaItemPropertyTitle"]) {
        [streamInfo appendString:metaData[@"MPMediaItemPropertyArtist"]];
        [streamInfo appendString:@" - "];
        [streamInfo appendString:metaData[@"MPMediaItemPropertyTitle"]];
    } else if (metaData[@"StreamTitle"]) {
        [streamInfo appendString:metaData[@"StreamTitle"]];
    }

    [self.stateTextFieldCell setTitle:streamInfo];
}

@end
