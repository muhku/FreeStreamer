/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSAudioStream.h"

#import "Reachability.h"

#include "audio_stream.h"
#include "stream_configuration.h"
#include "input_stream.h"

#import <AVFoundation/AVFoundation.h>

#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
#import <AudioToolbox/AudioToolbox.h>
#endif

#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 50000)
#import <MediaPlayer/MediaPlayer.h>
#endif

@implementation FSStreamConfiguration

- (id)init
{
    self = [super init];
    if (self) {
        NSMutableString *systemVersion = [[NSMutableString alloc] init];
        
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
        [systemVersion appendString:@"iOS "];
        [systemVersion appendString:[[UIDevice currentDevice] systemVersion]];
#else
        [systemVersion appendString:@"OS X"];
#endif
        
        self.bufferCount    = 8;
        self.bufferSize     = 32768;
        self.maxPacketDescs = 512;
        self.decodeQueueSize = 32;
        self.httpConnectionBufferSize = 1024;
        self.outputSampleRate = 44100;
        self.outputNumChannels = 2;
        self.bounceInterval    = 10;
        self.maxBounceCount    = 4;   // Max number of bufferings in bounceInterval seconds
        self.startupWatchdogPeriod = 30; // If the stream doesn't start to play in this seconds, the watchdog will fail it
        self.maxPrebufferedByteCount = 1000000; // 1 MB
        self.userAgent = [NSString stringWithFormat:@"FreeStreamer/%@ (%@)", freeStreamerReleaseVersion(), systemVersion];
        
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 60000)
        AVAudioSession *session = [AVAudioSession sharedInstance];
        double sampleRate = session.sampleRate;
        if (sampleRate > 0) {
            self.outputSampleRate = sampleRate;
        }
        NSInteger channels = session.outputNumberOfChannels;
        if (channels > 0) {
            self.outputNumChannels = channels;
        }
#endif
            
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
        /* iOS */
            
#ifdef __LP64__
        /* Running on iPhone 5s or later,
         * so the default configuration is OK
         */
#else
        /* 32-bit CPU, a bit older iPhone/iPad, increase
         *  the buffer sizes a bit.
         *
         * Discussed here:
         * https://github.com/muhku/FreeStreamer/issues/41
         */
        int scale = 2;
            
        self.bufferCount    *= scale;
        self.bufferSize     *= scale;
        self.maxPacketDescs *= scale;
#endif
#else
            /* OS X */
            
            // Default configuration is OK
        
            // No need to be so concervative with the cache sizes
            self.maxPrebufferedByteCount = 16000000; // 16 MB
#endif
    }
    
    return self;
}

@end

NSString *freeStreamerReleaseVersion()
{
    NSString *version = [NSString stringWithFormat:@"%i.%i.%i",
                         FREESTREAMER_VERSION_MAJOR,
                         FREESTREAMER_VERSION_MINOR,
                         FREESTREAMER_VERSION_REVISION];
    return version;
}

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
    
    void reset();
    
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
    NSString *_defaultContentType;
    Reachability *_reachability;
    FSSeekByteOffset _lastSeekByteOffset;
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
@property (nonatomic,assign) BOOL wasDisconnected;
@property (nonatomic,assign) BOOL wasContinuousStream;
@property (readonly) size_t prebufferedByteCount;
@property (readonly) FSSeekByteOffset currentSeekByteOffset;
@property (readonly) FSStreamConfiguration *configuration;
@property (readonly) NSString *formatDescription;
@property (copy) void (^onCompletion)();
@property (copy) void (^onFailure)();
@property (nonatomic,assign) FSAudioStreamError lastError;
@property (nonatomic,unsafe_unretained) id<FSPCMAudioStreamDelegate> delegate;
@property (nonatomic,unsafe_unretained) FSAudioStream *stream;

- (AudioStreamStateObserver *)streamStateObserver;

- (void)reachabilityChanged:(NSNotification *)note;
- (void)interruptionOccurred:(NSNotification *)notification;

- (void)play;
- (void)playFromURL:(NSURL*)url;
- (void)playFromOffset:(FSSeekByteOffset)offset;
- (void)stop;
- (BOOL)isPlaying;
- (void)pause;
- (void)seekToTime:(unsigned)newSeekTime;
- (void)setVolume:(float)volume;
- (void)setPlayRate:(float)playRate;
- (unsigned)timePlayedInSeconds;
- (unsigned)durationInSeconds;
- (astreamer::Input_Stream_Position)streamPositionForTime:(unsigned)newSeekTime;
@end

@implementation FSAudioStreamPrivate

-(id)init
{
    if (self = [super init]) {
        _url = nil;
        
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self stop];
    
    _delegate = nil;
    
    delete _audioStream, _audioStream = nil;
    delete _observer, _observer = nil;
}

- (AudioStreamStateObserver *)streamStateObserver
{
    return _observer;
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

- (void)playFromOffset:(FSSeekByteOffset)offset
{
    astreamer::Input_Stream_Position position;
    position.start = offset.start;
    position.end   = offset.end;
    
    _audioStream->open(&position);
    
    _audioStream->setSeekPosition(offset.position);
    _audioStream->setContentLength(offset.end);
    
    _observer->reset();
    
    [_reachability startNotifier];
}

- (void)setDefaultContentType:(NSString *)defaultContentType
{
    if (defaultContentType) {
        _defaultContentType = [defaultContentType copy];
        _audioStream->setDefaultContentType((__bridge CFStringRef)_defaultContentType);
    } else {
        _audioStream->setDefaultContentType(NULL);
    }
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
    CFStringRef c = _audioStream->contentType();
    if (c) {
        return CFBridgingRelease(CFStringCreateCopy(kCFAllocatorDefault, c));
    }
    return nil;
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

- (size_t)prebufferedByteCount
{
    return _audioStream->cachedDataSize();
}

- (FSSeekByteOffset)currentSeekByteOffset
{
    FSSeekByteOffset offset;
    offset.start    = 0;
    offset.end      = 0;
    offset.position = 0;
    
    // If continuous
    if ((0 == [self durationInSeconds])) {
        return offset;
    }
    
    offset.position = [self timePlayedInSeconds];
    
    astreamer::Input_Stream_Position httpStreamPos = [self streamPositionForTime:offset.position];
    
    offset.start = httpStreamPos.start;
    offset.end   = httpStreamPos.end;
    
    return offset;
}

- (FSStreamConfiguration *)configuration
{
    FSStreamConfiguration *config = [[FSStreamConfiguration alloc] init];
    
    astreamer::Stream_Configuration *c = astreamer::Stream_Configuration::configuration();
    
    config.bufferCount              = c->bufferCount;
    config.bufferSize               = c->bufferSize;
    config.maxPacketDescs           = c->maxPacketDescs;
    config.decodeQueueSize          = c->decodeQueueSize;
    config.httpConnectionBufferSize = c->httpConnectionBufferSize;
    config.outputSampleRate         = c->outputSampleRate;
    config.outputNumChannels        = c->outputNumChannels;
    config.bounceInterval           = c->bounceInterval;
    config.maxBounceCount           = c->maxBounceCount;
    config.startupWatchdogPeriod    = c->startupWatchdogPeriod;
    config.maxPrebufferedByteCount  = c->maxPrebufferedByteCount;
    
    if (c->userAgent) {
        // Let the Objective-C side handle the memory for the copy of the original user-agent
        config.userAgent = (__bridge_transfer NSString *)CFStringCreateCopy(kCFAllocatorDefault, c->userAgent);
    }

    return config;
}

- (NSString *)formatDescription
{
    return CFBridgingRelease(_audioStream->sourceFormatDescription());
}

- (void)reachabilityChanged:(NSNotification *)note
{
    Reachability *reach = [note object];
    NetworkStatus netStatus = [reach currentReachabilityStatus];
    BOOL internetConnectionAvailable = (netStatus == ReachableViaWiFi || netStatus == ReachableViaWWAN);
    
    if ([self isPlaying] && !internetConnectionAvailable) {
        self.wasDisconnected = YES;
        
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
        NSLog(@"FSAudioStream: Error: Internet connection disconnected while playing a stream.");
#endif
    }
    
    if (self.wasDisconnected && internetConnectionAvailable) {
        self.wasDisconnected = NO;
        
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
        NSLog(@"FSAudioStream: Internet connection available again. Restarting stream playback.");
#endif
        
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
            // Continuous streams do not have a duration.
            self.wasContinuousStream = (0 == [self durationInSeconds]);
            
            if (self.wasContinuousStream) {
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
                NSLog(@"FSAudioStream: Interruption began. Continuous stream. Stopping the stream.");
#endif
                [self stop];
            } else {
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
                NSLog(@"FSAudioStream: Interruption began. Non-continuous stream. Stopping the stream and saving the offset.");
#endif
                _lastSeekByteOffset = [self currentSeekByteOffset];
                [self stop];
            }
        }
    } else if ([interruptionType intValue] == AVAudioSessionInterruptionTypeEnded) {
        if (self.wasInterrupted) {
            self.wasInterrupted = NO;
            
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            
            if (self.wasContinuousStream) {
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
                NSLog(@"FSAudioStream: Interruption ended. Continuous stream. Starting the playback.");
#endif
                /*
                 * Resume playing.
                 */
                [self play];
            } else {
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
                NSLog(@"FSAudioStream: Interruption ended. Continuous stream. Playing from the offset");
#endif
                /*
                 * Resume playing.
                 */
               [self playFromOffset:_lastSeekByteOffset];
            }
        }
    }
#endif
}

- (void)play
{
    _audioStream->open();
    
    _observer->reset();

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

- (void)setPlayRate:(float)playRate
{
    _audioStream->setPlayRate(playRate);
}

- (unsigned)timePlayedInSeconds
{
    return _audioStream->timePlayedInSeconds();
}

- (unsigned)durationInSeconds
{
    return _audioStream->durationInSeconds();
}

- (astreamer::Input_Stream_Position)streamPositionForTime:(unsigned)newSeekTime
{
    return _audioStream->streamPositionForTime(newSeekTime);
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"[FreeStreamer %@] URL: %@\nbufferCount: %i\nbufferSize: %i\nmaxPacketDescs: %i\ndecodeQueueSize: %i\nhttpConnectionBufferSize: %i\noutputSampleRate: %f\noutputNumChannels: %ld\nbounceInterval: %i\nmaxBounceCount: %i\nstartupWatchdogPeriod: %i\nmaxPrebufferedByteCount: %i\nformat: %@\nuserAgent: %@",
            freeStreamerReleaseVersion(),
            self.url,
            self.configuration.bufferCount,
            self.configuration.bufferSize,
            self.configuration.maxPacketDescs,
            self.configuration.decodeQueueSize,
            self.configuration.httpConnectionBufferSize,
            self.configuration.outputSampleRate,
            self.configuration.outputNumChannels,
            self.configuration.bounceInterval,
            self.configuration.maxBounceCount,
            self.configuration.startupWatchdogPeriod,
            self.configuration.maxPrebufferedByteCount,
            self.formatDescription,
            self.configuration.userAgent];
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
    FSStreamConfiguration *defaultConfiguration = [[FSStreamConfiguration alloc] init];
    
    if (self = [self initWithConfiguration:defaultConfiguration]) {
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

- (id)initWithConfiguration:(FSStreamConfiguration *)configuration
{
    if (self = [super init]) {
        astreamer::Stream_Configuration *c = astreamer::Stream_Configuration::configuration();
        
        c->bufferCount              = configuration.bufferCount;
        c->bufferSize               = configuration.bufferSize;
        c->maxPacketDescs           = configuration.maxPacketDescs;
        c->decodeQueueSize          = configuration.decodeQueueSize;
        c->httpConnectionBufferSize = configuration.httpConnectionBufferSize;
        c->outputSampleRate         = configuration.outputSampleRate;
        c->outputNumChannels        = configuration.outputNumChannels;
        c->maxBounceCount           = configuration.maxBounceCount;
        c->bounceInterval           = configuration.bounceInterval;
        c->startupWatchdogPeriod    = configuration.startupWatchdogPeriod;
        c->maxPrebufferedByteCount  = configuration.maxPrebufferedByteCount;
        
        if (c->userAgent) {
            CFRelease(c->userAgent);
        }
        c->userAgent = CFStringCreateCopy(kCFAllocatorDefault, (__bridge CFStringRef)configuration.userAgent);
        
        _private = [[FSAudioStreamPrivate alloc] init];
        _private.stream = self;
    }
    return self;
}

- (void)dealloc
{
    AudioStreamStateObserver *observer = [_private streamStateObserver];
    
    // Break the cyclic loop so that dealloc() may be called
    observer->priv = nil;
    
    _private.stream = nil;
    _private.delegate = nil;
    
    _private = nil;
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

- (void)playFromOffset:(FSSeekByteOffset)offset
{
    [_private playFromOffset:offset];
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

- (void)setPlayRate:(float)playRate
{
    [_private setPlayRate:playRate];
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

- (FSSeekByteOffset)currentSeekByteOffset
{
    return _private.currentSeekByteOffset;
}

- (BOOL)continuous
{
    FSStreamPosition duration = self.duration;
    return (duration.minute == 0 && duration.second == 0);
}

- (size_t)prebufferedByteCount
{
    return _private.prebufferedByteCount;
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

- (FSStreamConfiguration *)configuration
{
    return _private.configuration;
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

-(NSString *)description
{
    return [_private description];
}

@end

/*
 * ===============================================================
 * AudioStreamStateObserver: listen to the state from the audio stream.
 * ===============================================================
 */

void AudioStreamStateObserver::reset()
{
    m_eofReached = false;
}

void AudioStreamStateObserver::audioStreamErrorOccurred(int errorCode)
{
    switch (errorCode) {
        case kFsAudioStreamErrorOpen:
            priv.lastError = kFsAudioStreamErrorOpen;
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Error opening the stream: %@", priv);
#endif
            
            break;
        case kFsAudioStreamErrorStreamParse:
            priv.lastError = kFsAudioStreamErrorStreamParse;
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Error parsing the stream: %@", priv);
#endif
            
            break;
        case kFsAudioStreamErrorNetwork:
            priv.lastError = kFsAudioStreamErrorNetwork;
        
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Network error: %@", priv);
#endif
            
            break;
        case kFsAudioStreamErrorUnsupportedFormat:
            priv.lastError = kFsAudioStreamErrorUnsupportedFormat;
    
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Unsupported format error: %@", priv);
#endif
            
            break;
            
        case kFsAudioStreamErrorStreamBouncing:
            priv.lastError = kFsAudioStreamErrorStreamBouncing;
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSAudioStream: Stream bounced: %@", priv);
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
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamBuffering];
            break;
        case astreamer::Audio_Stream::PLAYING:
            priv.lastError = kFsAudioStreamErrorNone;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamPlaying];
#if (__IPHONE_OS_VERSION_MIN_REQUIRED >= 40000)
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
#endif
            break;
        case astreamer::Audio_Stream::PAUSED:
            priv.lastError = kFsAudioStreamErrorNone;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamPaused];
            break;
        case astreamer::Audio_Stream::SEEKING:
            priv.lastError = kFsAudioStreamErrorNone;
            fsAudioState = [NSNumber numberWithInt:kFsAudioStreamSeeking];
            break;
        case astreamer::Audio_Stream::END_OF_FILE:
            priv.lastError = kFsAudioStreamErrorNone;
            m_eofReached = true;
            fsAudioState = [NSNumber numberWithInt:kFSAudioStreamEndOfFile];
            break;
        case astreamer::Audio_Stream::FAILED:
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