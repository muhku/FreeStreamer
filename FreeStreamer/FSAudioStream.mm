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
 * The notification proxy pumps messages from
 * the audio stream thread to the main thread.
 * ===============================================================
 */

@interface AudioStreamNotificationProxy : NSObject {}
+ (void)postNotificationOnMainThread:(NSNotification *)notification;
+ (void)postNotificationInternal:(NSNotification *)notification;
@end

@implementation AudioStreamNotificationProxy

+ (void)postNotificationOnMainThread:(NSNotification *)notification {
	[[self class]
        performSelectorOnMainThread:@selector(postNotificationInternal:)
        withObject:notification
        waitUntilDone:YES];
}

+ (void)postNotificationInternal:(NSNotification *)notification {
    NSAssert([[NSThread currentThread] isEqual:[NSThread mainThread]],
             @"Notification must be posted on the main thread.");
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}
@end

/*
 * ===============================================================
 * Listens to the state from the audio stream.
 * ===============================================================
 */

class AudioStreamStateObserver : public astreamer::Audio_Stream_Delegate
{
public:
    void audioStreamErrorOccurred(int errorCode)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:errorCode] forKey:FSAudioStreamNotificationKey_Error];
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamErrorNotification object:nil userInfo:userInfo];
        
        [AudioStreamNotificationProxy postNotificationOnMainThread:notification];
        
        [pool release];
    }
    
    void audioStreamStateChanged(astreamer::Audio_Stream::State state)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
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
                break;
        }
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fsAudioState forKey:FSAudioStreamNotificationKey_State];
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamStateChangeNotification object:nil userInfo:userInfo];
        
        [AudioStreamNotificationProxy postNotificationOnMainThread:notification];
        
        [pool release];
    }
    
    void audioStreamMetaDataAvailable(std::string metaData)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        NSString *s = [NSString stringWithUTF8String:metaData.c_str()];
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:s forKey:FSAudioStreamNotificationKey_MetaData];
        NSNotification *notification = [NSNotification notificationWithName:FSAudioStreamMetaDataNotification object:nil userInfo:userInfo];
        
        [AudioStreamNotificationProxy postNotificationOnMainThread:notification];
        
        [pool release];
    }
};

/*
 * ===============================================================
 * FSAudioStream private implementation
 * ===============================================================
 */

@interface FSAudioStreamPrivate : NSObject {
    astreamer::Audio_Stream *_audioStream;
    NSThread *_playbackThread;
    NSURL *_url;
    BOOL _shouldStart;
    BOOL _shouldExit;
	AudioStreamStateObserver *_observer;
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
- (void)audioPlaybackRunloop;
- (BOOL)isPlaying;
- (void)pause;
@end

@implementation FSAudioStreamPrivate

@synthesize wasInterrupted=_wasInterrupted;

-(id)init {
    if (self = [super init]) {
        _url = nil;
        _playbackThread = nil;
        _wasInterrupted = NO;

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
    
    if (_playbackThread) {
        _shouldExit = YES;
    }
	[super dealloc];
}

- (void)setUrl:(NSURL *)url {
    BOOL currentlyPlaying = (_playbackThread != nil);
    
    if (currentlyPlaying) {
        [self stop];
    }
    
    @synchronized (self) {
        if ([url isEqual:_url]) {
            return;
        }
        
        [_url release], _url = [url copy];
    }
    
    if (currentlyPlaying) {
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

- (void)audioPlaybackRunloop {    
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    NSAssert([[NSThread currentThread] isEqual:_playbackThread],
             @"Playback must happen in the playback thread.");
    
    _observer = new AudioStreamStateObserver();
    _audioStream = new astreamer::Audio_Stream((CFURLRef)_url);
    _audioStream->m_delegate = _observer;
#ifdef TARGET_OS_IPHONE      
    _backgroundTask = UIBackgroundTaskInvalid;
#endif    
    
	do {
        if (_shouldStart) {
            _shouldStart = NO;
            _audioStream->open();
        }
#ifdef TARGET_OS_IPHONE          
        if (_backgroundTask == UIBackgroundTaskInvalid) {
            _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
                _backgroundTask = UIBackgroundTaskInvalid;
            }];
        }
#endif
		[[NSRunLoop currentRunLoop]
         runMode:NSDefaultRunLoopMode
         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	} while (!_shouldExit);
    
    _audioStream->close();
    
    delete _audioStream, _audioStream = nil;
    delete _observer, _observer = nil;
    
#ifdef TARGET_OS_IPHONE    
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
        _backgroundTask = UIBackgroundTaskInvalid;
    }
#endif
    
    [_playbackThread release], _playbackThread = nil;
    
    [pool release];
}

- (void)play {
    NSAssert([[NSThread currentThread] isEqual:[NSThread mainThread]],
             @"Playback must be started from the main thread.");
    
    @synchronized (self) {
        if (!_url) {
            return;
        }
        
        _shouldStart = YES;
        
        if (!_playbackThread) {
            _playbackThread = [[NSThread alloc] initWithTarget:self selector:@selector(audioPlaybackRunloop) object:nil];
            [_playbackThread start];
        }
    }    
}

- (void)playFromURL:(NSURL*)url {
    [self setUrl:url];
    [self play];
}

- (void)stop {
    NSAssert([[NSThread currentThread] isEqual:[NSThread mainThread]],
             @"Stop must be called from the main thread.");
    
    @synchronized (self) {
        _shouldExit = YES;
        
        while (_playbackThread) {
            [[NSRunLoop currentRunLoop]
             runMode:NSDefaultRunLoopMode
             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        }
        
        _shouldExit = NO;
    }
}

- (BOOL)isPlaying {
    NSAssert([[NSThread currentThread] isEqual:[NSThread mainThread]],
             @"Stop must be called from the main thread.");
    
    return (_playbackThread != nil);
}

- (void)pause {
    NSAssert([[NSThread currentThread] isEqual:[NSThread mainThread]],
             @"Pause must be called from the main thread.");
    
    _audioStream->pause();
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
    /*
     * Note that the interruption listener will be called on the main
     * thread.
     */
	FSAudioStreamPrivate *THIS = (FSAudioStreamPrivate*)inClientData;
    
	if (inInterruptionState == kAudioSessionBeginInterruption) {
        if ([THIS isPlaying]) {
            THIS.wasInterrupted = YES;
            
            /* Internally, this will call AudioQueuePause(), which is safe
             *  to call from other than the audio playback thread.
             *
             * Don't try to call stop, it won't terminate the audio queue
             * correctly when called from the main thread.
             */
            [THIS pause];
        }
	} else if (inInterruptionState == kAudioSessionEndInterruption) {
        if (THIS.wasInterrupted) {
            THIS.wasInterrupted = NO;
            
            /*
             * Resume playing.
             */
            [THIS pause];
        }
    }
}
#endif