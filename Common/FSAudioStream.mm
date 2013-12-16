/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import "FSAudioStream.h"

#import "Reachability.h"

#include "audio_stream.h"

#import <AVFoundation/AVFoundation.h>

#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
#import <AudioToolbox/AudioToolbox.h>
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
@property (nonatomic,assign) BOOL wasInterrupted;
@property (copy) void (^onCompletion)();
@property (copy) void (^onFailure)();

- (void)reachabilityChanged:(NSNotification *)note;
- (void)interruptionOccurred:(NSNotification *)notification;

- (void)play;
- (void)playFromURL:(NSURL*)url;
- (void)stop;
- (BOOL)isPlaying;
- (void)pause;
- (void)seekToTime:(unsigned)newSeekTime;
- (unsigned)timePlayedInSeconds;
- (unsigned)durationInSeconds;
@end

@implementation FSAudioStreamPrivate

@synthesize wasInterrupted=_wasInterrupted;
@synthesize onCompletion;
@synthesize onFailure;

-(id)init {
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

- (void)dealloc {
    [_reachability stopNotifier];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _audioStream->close();
    
    delete _audioStream, _audioStream = nil;
    delete _observer, _observer = nil;
}

- (void)setUrl:(NSURL *)url {
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

- (NSURL*)url {
    if (!_url) {
        return nil;
    }
    
    NSURL *copyOfURL = [_url copy];
    return copyOfURL;
}

- (void)setStrictContentTypeChecking:(BOOL)strictContentTypeChecking {
    if (_strictContentTypeChecking == strictContentTypeChecking) {
        // No change
        return;
    }
    _strictContentTypeChecking = strictContentTypeChecking;
    _audioStream->setStrictContentTypeChecking(strictContentTypeChecking);
}

- (BOOL)strictContentTypeChecking {
    return _strictContentTypeChecking;
}

- (void)playFromURL:(NSURL*)url {
    [self setUrl:url];
    [self play];
}

- (void)setDefaultContentType:(NSString *)defaultContentType {
    _defaultContentType = [defaultContentType copy];
    std::string contentType([_defaultContentType UTF8String]);
    _audioStream->setDefaultContentType(contentType);
}

- (NSString*)defaultContentType {
    if (!_defaultContentType) {
        return nil;
    }
    
    NSString *copyOfDefaultContentType = [_defaultContentType copy];
    return copyOfDefaultContentType;
}

- (void)reachabilityChanged:(NSNotification *)note {
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

- (void)stop {
    _audioStream->close();
    
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
        _backgroundTask = UIBackgroundTaskInvalid;
    }
#endif
    
    [_reachability stopNotifier];
}

- (BOOL)isPlaying {
    return (_audioStream->state() == astreamer::Audio_Stream::PLAYING);
}

- (void)pause {
    _audioStream->pause();
}

- (void)seekToTime:(unsigned)newSeekTime {
    _audioStream->seekToTime(newSeekTime);
}

- (unsigned)timePlayedInSeconds {
    return _audioStream->timePlayedInSeconds();
}

- (unsigned)durationInSeconds {
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

-(id)init {
    if (self = [super init]) {
        _private = [[FSAudioStreamPrivate alloc] init];
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

- (void)setUrl:(NSURL *)url {
    [_private setUrl:url];
}

- (NSURL*)url {
    return [_private url];
}

- (void)setStrictContentTypeChecking:(BOOL)strictContentTypeChecking {
    [_private setStrictContentTypeChecking:strictContentTypeChecking];
}

- (BOOL)strictContentTypeChecking {
    return [_private strictContentTypeChecking];
}

- (void)setDefaultContentType:(NSString *)defaultContentType {
    [_private setDefaultContentType:defaultContentType];
}

- (NSString*)defaultContentType {
    return [_private defaultContentType];
}

- (void)play {
    [_private play];   
}

- (void)playFromURL:(NSURL*)url {
    [_private playFromURL:url];
}

- (void)stop {
    [_private stop];
}

- (void)pause {
    [_private pause];
}

- (void)seekToPosition:(FSStreamPosition)position {
    unsigned seekTime = position.minute * 60 + position.second;
    
    [_private seekToTime:seekTime];
}

- (BOOL)isPlaying
{
    return [_private isPlaying];
}

- (FSStreamPosition)currentTimePlayed {
    unsigned u = [_private timePlayedInSeconds];
    
    unsigned s,m;
    
    s = u % 60, u /= 60;
    m = u;
    
    FSStreamPosition pos = {.minute = m, .second = s};
    return pos;
}

- (FSStreamPosition)duration {
    unsigned u = [_private durationInSeconds];
    
    unsigned s,m;
    
    s = u % 60, u /= 60;
    m = u;
    
    FSStreamPosition pos = {.minute = m, .second = s};
    return pos;
}

- (BOOL)continuous {
    FSStreamPosition duration = self.duration;
    return (duration.minute == 0 && duration.second == 0);
}

- (void (^)())onCompletion {
    return _private.onCompletion;
}

- (void)setOnCompletion:(void (^)())onCompletion {
    _private.onCompletion = onCompletion;
}

- (void (^)())onFailure {
    return _private.onFailure;
}

- (void)setOnFailure:(void (^)())onFailure {
    _private.onFailure = onFailure;
}

@end

/*
 * ===============================================================
 * AudioStreamStateObserver: listen to the state from the audio stream.
 * ===============================================================
 */
    
void AudioStreamStateObserver::audioStreamErrorOccurred(int errorCode)
{
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
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamStopped];
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
            [[AVAudioSession sharedInstance] setActive:NO error:nil];
#endif
            if (m_eofReached && priv.onCompletion) {
                priv.onCompletion();
            }
            break;
        case astreamer::Audio_Stream::BUFFERING:
            m_eofReached = false;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamBuffering];
            break;
        case astreamer::Audio_Stream::PLAYING:
            m_eofReached = false;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamPlaying];
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
#endif
            break;
        case astreamer::Audio_Stream::SEEKING:
            m_eofReached = false;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamSeeking];
            break;
        case astreamer::Audio_Stream::END_OF_FILE:
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
    
    NSDictionary *userInfo = @{FSAudioStreamNotificationKey_MetaData: metaDataDictionary,
                              FSAudioStreamNotificationKey_Stream: [NSValue valueWithPointer:source]};
    NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamMetaDataNotification object:nil userInfo:userInfo];
    
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}
