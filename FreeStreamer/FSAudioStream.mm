/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSAudioStream.h"

#include "astreamer/audio_stream.h"

#ifdef TARGET_OS_IPHONE
#import <AudioToolbox/AudioToolbox.h>
#endif

NSString* const FSAudioStreamStateChangeNotification = @"FSAudioStreamStateChangeNotification";
NSString* const FSAudioStreamNotificationKey_Stream = @"stream";
NSString* const FSAudioStreamNotificationKey_State = @"state";

NSString* const FSAudioStreamErrorNotification = @"FSAudioStreamErrorNotification";
NSString* const FSAudioStreamNotificationKey_Error = @"error";

NSString* const FSAudioStreamMetaDataNotification = @"FSAudioStreamMetaDataNotification";
NSString* const FSAudioStreamNotificationKey_MetaData = @"metadata";

#ifdef TARGET_OS_IPHONE
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
#ifdef TARGET_OS_IPHONE         
                AudioSessionSetActive(false);
#endif
                break;
            case astreamer::Audio_Stream::BUFFERING:
                fsAudioState = [NSNumber numberWithInt:kFsAudioStreamBuffering];
                break;
            case astreamer::Audio_Stream::PLAYING:
                fsAudioState = [NSNumber numberWithInt:kFsAudioStreamPlaying];
#ifdef TARGET_OS_IPHONE         
                AudioSessionSetActive(true);
#endif                
                break;
            case astreamer::Audio_Stream::FAILED:
                fsAudioState = [NSNumber numberWithInt:kFsAudioStreamFailed];
#ifdef TARGET_OS_IPHONE         
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
	AudioStreamStateObserver *_observer;
    BOOL _currentlyPlaying;
    BOOL _wasInterrupted;
#ifdef TARGET_OS_IPHONE    
    UIBackgroundTaskIdentifier _backgroundTask;
#endif
}

@property (nonatomic,assign) NSURL *url;
@property (nonatomic,assign) BOOL wasInterrupted;

- (void)play;
- (void)playFromURL:(NSURL*)url;
- (void)stop;
- (BOOL)isPlaying;
- (void)pause;
- (unsigned)timePlayedInSeconds;
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

#ifdef TARGET_OS_IPHONE        
        OSStatus result = AudioSessionInitialize(NULL,
                                                 NULL,
                                                 interruptionListener,
                                                 self);
        
        if (result == kAudioSessionNoError) {
            UInt32 category = kAudioSessionCategory_MediaPlayback;
            (void)AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
        }
#endif
    }
    return self;
}

- (void)dealloc {
    [_url release], _url = nil;
    
    _audioStream->close();
    
    delete _audioStream, _audioStream = nil;
    delete _observer, _observer = nil;

	[super dealloc];
}

- (void)setUrl:(NSURL *)url {
    if (_currentlyPlaying) {
        [self stop];
    }
    
    @synchronized (self) {
        if ([url isEqual:_url]) {
            return;
        }
        
        [_url release], _url = [url copy];
        
        _audioStream->setUrl((CFURLRef)_url);
    }
    
    if (_currentlyPlaying) {
        [self play];
    }
}

- (NSURL*)url {
    if (!_url) {
        return nil;
    }
    
    NSURL *copyOfURL = [[_url copy] autorelease];
    return copyOfURL;
}

- (void)playFromURL:(NSURL*)url {
    [self setUrl:url];
    [self play];
}

- (void)play
{
    _audioStream->open();
}

- (void)stop {
    _audioStream->close();
    _currentlyPlaying = NO;
    
#ifdef TARGET_OS_IPHONE    
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

- (unsigned)timePlayedInSeconds {
    return _audioStream->timePlayedInSeconds();
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

- (void)dealloc {
	[_private release], _private = nil;
	[super dealloc];
}

- (void)setUrl:(NSURL *)url {
    [_private setUrl:url];
}

- (NSURL*)url {
    return [_private url];
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

- (FSPlaybackTime)currentTimePlayed {
    unsigned u = [_private timePlayedInSeconds];
    
    unsigned s,m;

    s = u % 60, u /= 60;
    m = u % 60, u /= 60;
    
    FSPlaybackTime time = {.minute = m, .second = s};
    return time;
}

@end

/*
 * ===============================================================
 * Interruption listener for the audio session
 * ===============================================================
 */

#ifdef TARGET_OS_IPHONE
static void interruptionListener(void *	inClientData,
                                UInt32	inInterruptionState)
{
	FSAudioStreamPrivate *THIS = (FSAudioStreamPrivate*)inClientData;
    
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