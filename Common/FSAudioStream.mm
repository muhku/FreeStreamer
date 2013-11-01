/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSAudioStream.h"

#include "audio_stream.h"

#if !defined(TARGET_OS_MAC)
#import <AudioToolbox/AudioToolbox.h>
#endif

NSString* const FSAudioStreamStateChangeNotification = @"FSAudioStreamStateChangeNotification";
NSString* const FSAudioStreamNotificationKey_Stream = @"stream";
NSString* const FSAudioStreamNotificationKey_State = @"state";

NSString* const FSAudioStreamErrorNotification = @"FSAudioStreamErrorNotification";
NSString* const FSAudioStreamNotificationKey_Error = @"error";

NSString* const FSAudioStreamMetaDataNotification = @"FSAudioStreamMetaDataNotification";
NSString* const FSAudioStreamNotificationKey_MetaData = @"metadata";

#if !defined(TARGET_OS_MAC)
static void interruptionListener(void *	inClientData,
                                UInt32	inInterruptionState);
#endif

/*
 * ===============================================================
 * Listens to the state from the audio stream.
 * ===============================================================
 */

class AudioStreamStateObserver : public astreamer::Audio_Stream_Delegate
{
public:
    astreamer::Audio_Stream *source;
    
    void audioStreamErrorOccurred(int errorCode)
    {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithInt:errorCode], FSAudioStreamNotificationKey_Error,
                                  [NSValue valueWithPointer:source], FSAudioStreamNotificationKey_Stream, nil];
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamErrorNotification object:nil userInfo:userInfo];
        
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
    
    void audioStreamStateChanged(astreamer::Audio_Stream::State state)
    {
        NSNumber *fsAudioState;
        
        switch (state) {
            case astreamer::Audio_Stream::STOPPED:
                fsAudioState = [NSNumber numberWithInt:kFsAudioStreamStopped];
#if !defined(TARGET_OS_MAC)
                AudioSessionSetActive(false);
#endif
                break;
            case astreamer::Audio_Stream::BUFFERING:
                fsAudioState = [NSNumber numberWithInt:kFsAudioStreamBuffering];
                break;
            case astreamer::Audio_Stream::PLAYING:
                fsAudioState = [NSNumber numberWithInt:kFsAudioStreamPlaying];
#if !defined(TARGET_OS_MAC)
                AudioSessionSetActive(true);
#endif                
                break;
            case astreamer::Audio_Stream::SEEKING:
                fsAudioState = [NSNumber numberWithInt:kFsAudioStreamSeeking];
                break;
            case astreamer::Audio_Stream::END_OF_FILE:
                fsAudioState = [NSNumber numberWithInt:kFSAudioStreamEndOfFile];
                break;
            case astreamer::Audio_Stream::FAILED:
                fsAudioState = [NSNumber numberWithInt:kFsAudioStreamFailed];
#if !defined(TARGET_OS_MAC)
                AudioSessionSetActive(false);
#endif                
                break;
            default:
                /* unknown state */
                return;
                
                break;
        }
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                        fsAudioState, FSAudioStreamNotificationKey_State,
                        [NSValue valueWithPointer:source], FSAudioStreamNotificationKey_Stream, nil];
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamStateChangeNotification object:nil userInfo:userInfo];
        
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
    
    void audioStreamMetaDataAvailable(std::string metaData)
    {
        NSString *s = [NSString stringWithUTF8String:metaData.c_str()];
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                  s, FSAudioStreamNotificationKey_MetaData,
                                  [NSValue valueWithPointer:source], FSAudioStreamNotificationKey_Stream, nil];
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamMetaDataNotification object:nil userInfo:userInfo];
        
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
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
    BOOL _currentlyPlaying;
    BOOL _wasInterrupted;
    NSString *_defaultContentType;
#if !defined(TARGET_OS_MAC)
    UIBackgroundTaskIdentifier _backgroundTask;
#endif
}

@property (nonatomic,assign) NSURL *url;
@property (nonatomic,assign) BOOL strictContentTypeChecking;
@property (nonatomic,assign) NSString *defaultContentType;
@property (nonatomic,assign) BOOL wasInterrupted;

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

-(id)init {
    if (self = [super init]) {
        _url = nil;
        _wasInterrupted = NO;
        
        _observer = new AudioStreamStateObserver();
        _audioStream = new astreamer::Audio_Stream();
        _observer->source = _audioStream;
        _audioStream->m_delegate = _observer;

#if !defined(TARGET_OS_MAC)
        OSStatus result = AudioSessionInitialize(NULL,
                                                 NULL,
                                                 interruptionListener,
                                                 (__bridge void*)self);
        
        if (result == kAudioSessionNoError) {
            UInt32 category = kAudioSessionCategory_MediaPlayback;
            (void)AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
        }
#endif
    }
    return self;
}

- (void)dealloc {
    _audioStream->close();
    
    delete _audioStream, _audioStream = nil;
    delete _observer, _observer = nil;
}

- (void)setUrl:(NSURL *)url {
    if (_currentlyPlaying) {
        [self stop];
    }
    
    @synchronized (self) {
        if ([url isEqual:_url]) {
            return;
        }
        
        _url = [url copy];
        
        _audioStream->setUrl((__bridge CFURLRef)_url);
    }
    
    if (_currentlyPlaying) {
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

- (void)play
{
    _audioStream->open();
}

- (void)stop {
    _audioStream->close();
    _currentlyPlaying = NO;
    
#if !defined(TARGET_OS_MAC)
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
        _backgroundTask = UIBackgroundTaskInvalid;
    }
#endif

}

- (BOOL)isPlaying {
    return _currentlyPlaying;
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

@end

/*
 * ===============================================================
 * Interruption listener for the audio session
 * ===============================================================
 */

#if !defined(TARGET_OS_MAC)
static void interruptionListener(void *	inClientData,
                                UInt32	inInterruptionState)
{
	FSAudioStreamPrivate *THIS = (__bridge FSAudioStreamPrivate*)inClientData;
    
	if (inInterruptionState == kAudioSessionBeginInterruption) {
        if ([THIS isPlaying]) {
            THIS.wasInterrupted = YES;
            
            [THIS pause];
        }
	} else if (inInterruptionState == kAudioSessionEndInterruption) {
        if (THIS.wasInterrupted) {
            THIS.wasInterrupted = NO;
            
            AudioSessionSetActive(true);
            
            /*
             * Resume playing.
             */
            [THIS pause];
        }
    }
}
#endif