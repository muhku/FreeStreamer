/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

extern NSString* const FSAudioStreamStateChangeNotification;
extern NSString* const FSAudioStreamNotificationKey_State;

extern NSString* const FSAudioStreamErrorNotification;
extern NSString* const FSAudioStreamNotificationKey_Error;

extern NSString* const FSAudioStreamMetaDataNotification;
extern NSString* const FSAudioStreamNotificationKey_MetaData;

typedef enum {
    kFsAudioStreamRetrievingURL,
    kFsAudioStreamStopped,
    kFsAudioStreamBuffering,
    kFsAudioStreamPlaying,
    kFsAudioStreamSeeking,
    kFSAudioStreamEndOfFile,
    kFsAudioStreamFailed
} FSAudioStreamState;

typedef enum {
    kFsAudioStreamErrorOpen = 1,
    kFsAudioStreamErrorStreamParse = 2,
    kFsAudioStreamErrorNetwork = 3
} FSAudioStreamError;

@class FSAudioStreamPrivate;

typedef struct {
    unsigned minute;
    unsigned second;
} FSStreamPosition;

@interface FSAudioStream : NSObject {
    FSAudioStreamPrivate *_private;
}

- (id)initWithUrl:(NSURL *)url;
- (void)play;
- (void)playFromURL:(NSURL*)url;
- (void)stop;
/*
 * If the stream is playing, the stream playback is paused upon calling pause.
 * Otherwise (the stream is paused), calling pause will continue the playback.
 */
- (void)pause;
- (void)seekToPosition:(FSStreamPosition)position;
- (BOOL)isPlaying;

@property (nonatomic,assign) NSURL *url;
@property (nonatomic,assign) BOOL strictContentTypeChecking;
@property (nonatomic,assign) NSString *defaultContentType;
@property (nonatomic,readonly) FSStreamPosition currentTimePlayed;
@property (nonatomic,readonly) FSStreamPosition duration;
@property (nonatomic,readonly) BOOL continuous;

/*
 * Called upon completion of the stream. Note that for continuous
 * streams this is never called.
 */
@property (copy) void (^onCompletion)();
/*
 * Called upon a failure.
 */
@property (copy) void (^onFailure)();

@end