/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import "FSAudioStream.h"

#import "Reachability.h"

#include "audio_stream.h"

#import <AVFoundation/AVFoundation.h>

#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
#import <AudioToolbox/AudioToolbox.h>
#endif

#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 50000)
#import <MediaPlayer/MediaPlayer.h>
#endif

NSString* const FSAudioStreamStateChangeNotification = @"FSAudioStreamStateChangeNotification";
NSString* const FSAudioStreamNotificationKey_Stream = @"stream";
NSString* const FSAudioStreamNotificationKey_State = @"state";

NSString* const FSAudioStreamErrorNotification = @"FSAudioStreamErrorNotification";
NSString* const FSAudioStreamNotificationKey_Error = @"error";

NSString* const FSAudioStreamMetaDataNotification = @"FSAudioStreamMetaDataNotification";
NSString* const FSAudioStreamNotificationKey_MetaData = @"metadata";

class AudioStreamStateObserver : public astreamer::Audio_Stream_Delegate
{
private:
    bool m_eofReached;
    
public:
    astreamer::Audio_Stream *source;
    FSAudioStreamPrivate *priv;
    
    void audioStreamErrorOccurred(int errorCode);
    void audioStreamStateChanged(astreamer::Audio_Stream::State state);
    void audioStreamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData);
    void samplesAvailable(AudioBufferList samples, AudioStreamPacketDescription description);
};

/*
 * ===============================================================
 * FSAudioStream private implementation
 * ===============================================================
 */

@interface FSAudioStreamPrivate : NSObject {
    astreamer::Audio_Stream *_audioStream;
    NSURL *_url;
    BOOL _strictContentTypeChecking;
	AudioStreamStateObserver *_observer;
    BOOL _wasInterrupted;
    BOOL _wasDisconnected;
    NSString *_defaultContentType;
    Reachability *_reachability;
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
    UIBackgroundTaskIdentifier _backgroundTask;
#endif
}

@property (nonatomic,assign) NSURL *url;
@property (nonatomic,assign) BOOL strictContentTypeChecking;
@property (nonatomic,assign) NSString *defaultContentType;
@property (nonatomic,assign) NSString *contentType;
@property (nonatomic,assign) NSString *suggestedFileExtension;
@property (nonatomic,assign) NSURL *outputFile;
@property (nonatomic,assign) BOOL wasInterrupted;
@property (copy) void (^onCompletion)();
@property (copy) void (^onFailure)();
@property (nonatomic,assign) FSAudioStreamError lastError;
@property (nonatomic,unsafe_unretained) id<FSPCMAudioStreamDelegate> delegate;
@property (nonatomic,unsafe_unretained) FSAudioStream *stream;

- (void)reachabilityChanged:(NSNotification *)note;
- (void)interruptionOccurred:(NSNotification *)notification;

- (void)play;
- (void)playFromURL:(NSURL*)url;
- (void)stop;
- (BOOL)isPlaying;
- (void)pause;
- (void)seekToTime:(unsigned)newSeekTime;
- (void)setVolume:(float)volume;
- (unsigned)timePlayedInSeconds;
- (unsigned)durationInSeconds;
@end

@implementation FSAudioStreamPrivate

-(id)init
{
    if (self = [super init]) {
        _url = nil;
        _wasInterrupted = NO;
        _wasDisconnected = NO;
        
        _observer = new AudioStreamStateObserver();
        _observer->priv = self;
        _audioStream = new astreamer::Audio_Stream();
        _observer->source = _audioStream;
        _audioStream->m_delegate = _observer;
        
        _reachability = [Reachability reachabilityForInternetConnection];
        
        self.lastError = kFsAudioStreamErrorNone;
        
        _delegate = nil;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reachabilityChanged:)
                                                     name:kReachabilityChangedNotification
                                                   object:nil];

#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
#endif
        
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 60000)
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(interruptionOccurred:)
                                                     name:AVAudioSessionInterruptionNotification
                                                   object:nil];
#endif
    }
    return self;
}

- (void)dealloc
{
    [_reachability stopNotifier];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _audioStream->close();
    
    delete _audioStream, _audioStream = nil;
    delete _observer, _observer = nil;
}

- (void)setUrl:(NSURL *)url
{
    if ([self isPlaying]) {
        [self stop];
    }
    
    @synchronized (self) {
        if ([url isEqual:_url]) {
            return;
        }
        
        _url = [url copy];
        
        _audioStream->setUrl((__bridge CFURLRef)_url);
    }
    
    if ([self isPlaying]) {
        [self play];
    }
}

- (NSURL*)url
{
    if (!_url) {
        return nil;
    }
    
    NSURL *copyOfURL = [_url copy];
    return copyOfURL;
}

- (void)setStrictContentTypeChecking:(BOOL)strictContentTypeChecking
{
    if (_strictContentTypeChecking == strictContentTypeChecking) {
        // No change
        return;
    }
    _strictContentTypeChecking = strictContentTypeChecking;
    _audioStream->setStrictContentTypeChecking(strictContentTypeChecking);
}

- (BOOL)strictContentTypeChecking
{
    return _strictContentTypeChecking;
}

- (void)playFromURL:(NSURL*)url
{
    [self setUrl:url];
    [self play];
}

- (void)setDefaultContentType:(NSString *)defaultContentType
{
    _defaultContentType = [defaultContentType copy];
    std::string contentType([_defaultContentType UTF8String]);
    _audioStream->setDefaultContentType(contentType);
}

- (NSString*)defaultContentType
{
    if (!_defaultContentType) {
        return nil;
    }
    
    NSString *copyOfDefaultContentType = [_defaultContentType copy];
    return copyOfDefaultContentType;
}

- (NSString*)contentType
{
    return [NSString stringWithUTF8String:_audioStream->contentType().c_str()];
}

- (NSString*)suggestedFileExtension
{
    NSString *contentType = [self contentType];
    NSString *suggestedFileExtension = nil;
    
    if ([contentType isEqualToString:@"audio/mpeg"]) {
        suggestedFileExtension = @"mp3";
    } else if ([contentType isEqualToString:@"audio/x-wav"]) {
        suggestedFileExtension = @"wav";
    } else if ([contentType isEqualToString:@"audio/x-aifc"]) {
        suggestedFileExtension = @"aifc";
    } else if ([contentType isEqualToString:@"audio/x-aiff"]) {
        suggestedFileExtension = @"aiff";
    } else if ([contentType isEqualToString:@"audio/x-m4a"]) {
        suggestedFileExtension = @"m4a";
    } else if ([contentType isEqualToString:@"audio/mp4"]) {
        suggestedFileExtension = @"mp4";
    } else if ([contentType isEqualToString:@"audio/x-caf"]) {
        suggestedFileExtension = @"caf";
    }
    else if ([contentType isEqualToString:@"audio/aac"] ||
             [contentType isEqualToString:@"audio/aacp"]) {
        suggestedFileExtension = @"aac";
    }
    return suggestedFileExtension;
}

- (NSURL*)outputFile
{
    CFURLRef url = _audioStream->outputFile();
    if (url) {
        NSURL *u = (__bridge NSURL*)url;
        return [u copy];
    }
    return nil;
}

- (void)setOutputFile:(NSURL *)outputFile
{
    if (!outputFile) {
        _audioStream->setOutputFile(NULL);
        return;
    }
    NSURL *copyOfURL = [outputFile copy];
    _audioStream->setOutputFile((__bridge CFURLRef)copyOfURL);
}

- (void)reachabilityChanged:(NSNotification *)note
{
    Reachability *reach = [note object];
    NetworkStatus netStatus = [reach currentReachabilityStatus];
    BOOL internetConnectionAvailable = (netStatus == ReachableViaWiFi || netStatus == ReachableViaWWAN);
    
    if ([self isPlaying] && !internetConnectionAvailable) {
        _wasDisconnected = YES;
    }
    
    if (_wasDisconnected && internetConnectionAvailable) {
        _wasDisconnected = NO;
        
        /*
         * If we call play immediately after the reachability notification,
         * the network still fails. Give some time for the network to be actually
         * connected.
         */
        [NSTimer scheduledTimerWithTimeInterval:1
                                         target:self
                                       selector:@selector(play)
                                       userInfo:nil
                                        repeats:NO];
    }
}

- (void)interruptionOccurred:(NSNotification *)notification
{
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 60000)
    NSNumber *interruptionType = [[notification userInfo] valueForKey:AVAudioSessionInterruptionTypeKey];
    if ([interruptionType intValue] == AVAudioSessionInterruptionTypeBegan) {
        if ([self isPlaying]) {
            self.wasInterrupted = YES;
            
            [self pause];
        }
    } else if ([interruptionType intValue] == AVAudioSessionInterruptionTypeEnded) {
        if (self.wasInterrupted) {
            self.wasInterrupted = NO;
            
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            
            /*
             * Resume playing.
             */
            [self pause];
        }
    }
#endif
}

- (void)play
{
    _audioStream->open();
    
    [_reachability startNotifier];
}

- (void)stop
{
    _audioStream->close();
    
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
        _backgroundTask = UIBackgroundTaskInvalid;
    }
#endif
    
    [_reachability stopNotifier];
}

- (BOOL)isPlaying
{
    return (_audioStream->state() == astreamer::Audio_Stream::PLAYING);
}

- (void)pause
{
    _audioStream->pause();
}

- (void)seekToTime:(unsigned)newSeekTime
{
    _audioStream->seekToTime(newSeekTime);
}

- (void)setVolume:(float)volume
{
    _audioStream->setVolume(volume);
}

- (unsigned)timePlayedInSeconds
{
    return _audioStream->timePlayedInSeconds();
}

- (unsigned)durationInSeconds
{
    return _audioStream->durationInSeconds();
}

@end

/*
 * ===============================================================
 * FSAudioStream public implementation, merely wraps the
 * private class.
 * ===============================================================
 */

@implementation FSAudioStream

-(id)init
{
    if (self = [super init]) {
        _private = [[FSAudioStreamPrivate alloc] init];
        _private.stream = self;
    }
    return self;
}

- (id)initWithUrl:(NSURL *)url
{
    if (self = [self init]) {
        _private.url = url;
    }
    return self;
}

- (void)setUrl:(NSURL *)url
{
    [_private setUrl:url];
}

- (NSURL*)url
{
    return [_private url];
}

- (void)setStrictContentTypeChecking:(BOOL)strictContentTypeChecking
{
    [_private setStrictContentTypeChecking:strictContentTypeChecking];
}

- (BOOL)strictContentTypeChecking
{
    return [_private strictContentTypeChecking];
}

- (NSURL*)outputFile
{
    return [_private outputFile];
}

- (void)setOutputFile:(NSURL *)outputFile
{
    [_private setOutputFile:outputFile];
}

- (void)setDefaultContentType:(NSString *)defaultContentType
{
    [_private setDefaultContentType:defaultContentType];
}

- (NSString*)defaultContentType
{
    return [_private defaultContentType];
}

- (NSString*)contentType
{
    return [_private contentType];
}

- (NSString*)suggestedFileExtension
{
    return [_private suggestedFileExtension];
}

- (void)play
{
    [_private play];   
}

- (void)playFromURL:(NSURL*)url
{
    [_private playFromURL:url];
}

- (void)stop
{
    [_private stop];
}

- (void)pause
{
    [_private pause];
}

- (void)seekToPosition:(FSStreamPosition)position
{
    unsigned seekTime = position.minute * 60 + position.second;
    
    [_private seekToTime:seekTime];
}

- (void)setVolume:(float)volume
{
    [_private setVolume:volume];
}

- (BOOL)isPlaying
{
    return [_private isPlaying];
}

- (FSStreamPosition)currentTimePlayed
{
    unsigned u = [_private timePlayedInSeconds];
    
    unsigned s,m;
    
    s = u % 60, u /= 60;
    m = u;
    
    FSStreamPosition pos = {.minute = m, .second = s};
    return pos;
}

- (FSStreamPosition)duration
{
    unsigned u = [_private durationInSeconds];
    
    unsigned s,m;
    
    s = u % 60, u /= 60;
    m = u;
    
    FSStreamPosition pos = {.minute = m, .second = s};
    return pos;
}

- (BOOL)continuous
{
    FSStreamPosition duration = self.duration;
    return (duration.minute == 0 && duration.second == 0);
}

- (void (^)())onCompletion
{
    return _private.onCompletion;
}

- (void)setOnCompletion:(void (^)())onCompletion
{
    _private.onCompletion = onCompletion;
}

- (void (^)())onFailure
{
    return _private.onFailure;
}

- (void)setOnFailure:(void (^)())onFailure
{
    _private.onFailure = onFailure;
}

- (FSAudioStreamError)lastError
{
    return _private.lastError;
}

- (void)setDelegate:(id<FSPCMAudioStreamDelegate>)delegate
{
    _private.delegate = delegate;
}

- (id<FSPCMAudioStreamDelegate>)delegate
{
    return _private.delegate;
}

@end

/*
 * ===============================================================
 * AudioStreamStateObserver: listen to the state from the audio stream.
 * ===============================================================
 */
    
void AudioStreamStateObserver::audioStreamErrorOccurred(int errorCode)
{
    switch (errorCode) {
        case kFsAudioStreamErrorOpen:
            priv.lastError = kFsAudioStreamErrorOpen;
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Error opening the stream: %@", priv.url);
#endif
            
            break;
        case kFsAudioStreamErrorStreamParse:
            priv.lastError = kFsAudioStreamErrorStreamParse;
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Error parsing the stream: %@", priv.url);
#endif
            
            break;
        case kFsAudioStreamErrorNetwork:
            priv.lastError = kFsAudioStreamErrorNetwork;
        
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Network error: %@", priv.url);
#endif
            
            break;
        case kFsAudioStreamErrorUnsupportedFormat:
            priv.lastError = kFsAudioStreamErrorUnsupportedFormat;
    
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Unsupported format error: %@", priv.url);
#endif
            
            break;
        default:
            break;
    }
    
    NSDictionary *userInfo = @{FSAudioStreamNotificationKey_Error: @(errorCode),
                              FSAudioStreamNotificationKey_Stream: [NSValue valueWithPointer:source]};
    NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamErrorNotification object:nil userInfo:userInfo];
    
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}
    
void AudioStreamStateObserver::audioStreamStateChanged(astreamer::Audio_Stream::State state)
{
    NSNumber *fsAudioState;
    
    switch (state) {
        case astreamer::Audio_Stream::STOPPED:
            priv.lastError = kFsAudioStreamErrorNone;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamStopped];
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
            [[AVAudioSession sharedInstance] setActive:NO error:nil];
#endif
            if (m_eofReached && priv.onCompletion) {
                priv.onCompletion();
            }
            break;
        case astreamer::Audio_Stream::BUFFERING:
            priv.lastError = kFsAudioStreamErrorNone;
            m_eofReached = false;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamBuffering];
            break;
        case astreamer::Audio_Stream::PLAYING:
            priv.lastError = kFsAudioStreamErrorNone;
            m_eofReached = false;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamPlaying];
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
#endif
            break;
        case astreamer::Audio_Stream::SEEKING:
            priv.lastError = kFsAudioStreamErrorNone;
            m_eofReached = false;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamSeeking];
            break;
        case astreamer::Audio_Stream::END_OF_FILE:
            priv.lastError = kFsAudioStreamErrorNone;
            m_eofReached = true;
            fsAudioState = [NSNumber numberWithInt:kFSAudioStreamEndOfFile];
            break;
        case astreamer::Audio_Stream::FAILED:
            m_eofReached = false;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamFailed];
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
            [[AVAudioSession sharedInstance] setActive:NO error:nil];
#endif
            if (priv.onFailure) {
                priv.onFailure();
            }
            break;
        default:
            /* unknown state */
            return;
            
            break;
    }
    
    NSDictionary *userInfo = @{FSAudioStreamNotificationKey_State: fsAudioState,
                              FSAudioStreamNotificationKey_Stream: [NSValue valueWithPointer:source]};
    NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamStateChangeNotification object:nil userInfo:userInfo];
    
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}
    
void AudioStreamStateObserver::audioStreamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData)
{
    NSMutableDictionary *metaDataDictionary = [[NSMutableDictionary alloc] init];
    
    for (std::map<CFStringRef,CFStringRef>::iterator iter = metaData.begin(); iter != metaData.end(); ++iter) {
        CFStringRef key = iter->first;
        CFStringRef value = iter->second;
        
        metaDataDictionary[CFBridgingRelease(key)] = CFBridgingRelease(value);
    }
    
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 50000)
    NSMutableDictionary *songInfo = [[NSMutableDictionary alloc] init];
    
    if (metaDataDictionary[@"MPMediaItemPropertyTitle"]) {
        songInfo[MPMediaItemPropertyTitle] = metaDataDictionary[@"MPMediaItemPropertyTitle"];
    } else if (metaDataDictionary[@"StreamTitle"]) {
        songInfo[MPMediaItemPropertyTitle] = metaDataDictionary[@"StreamTitle"];
    }
    
    if (metaDataDictionary[@"MPMediaItemPropertyArtist"]) {
        songInfo[MPMediaItemPropertyArtist] = metaDataDictionary[@"MPMediaItemPropertyArtist"];
    }
    
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:songInfo];
#endif
    
    NSDictionary *userInfo = @{FSAudioStreamNotificationKey_MetaData: metaDataDictionary,
                              FSAudioStreamNotificationKey_Stream: [NSValue valueWithPointer:source]};
    NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamMetaDataNotification object:nil userInfo:userInfo];
    
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

void AudioStreamStateObserver::samplesAvailable(AudioBufferList samples, AudioStreamPacketDescription description)
{
    if ([priv.delegate respondsToSelector:@selector(audioStream:samplesAvailable:count:)]) {
        int16_t *buffer = (int16_t *)samples.mBuffers[0].mData;
        NSUInteger count = description.mDataByteSize / sizeof(int16_t);
        
        [priv.delegate audioStream:priv.stream samplesAvailable:buffer count:count];
    }
}