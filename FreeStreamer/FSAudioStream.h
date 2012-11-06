/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
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

- (void)play;
- (void)playFromURL:(NSURL*)url;
- (void)stop;
- (void)pause;
- (void)seekToPosition:(FSStreamPosition)position;

@property (nonatomic,assign) NSURL *url;
@property (nonatomic,readonly) FSStreamPosition currentTimePlayed;
@property (nonatomic,readonly) FSStreamPosition duration;
@property (nonatomic,readonly) BOOL continuous;

@end
