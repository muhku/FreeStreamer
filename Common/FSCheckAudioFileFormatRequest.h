/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

typedef enum {
    kFSAudioFileFormatUnknown = 0,
    
    /* Playlist */
    kFSAudioFileFormatM3UPlaylist,
    kFSAudioFileFormatPLSPlaylist,
    
    /* Audio file */
    kFSAudioFileFormatMP3,
    kFSAudioFileFormatWAVE,
    kFSAudioFileFormatAIFC,
    kFSAudioFileFormatAIFF,
    kFSAudioFileFormatM4A,
    kFSAudioFileFormatMPEG4,
    kFSAudioFileFormatCAF,
    kFSAudioFileFormatAAC_ADTS,
    
    kFSAudioFileFormatCount
} FSAudioFileFormat;

@interface FSCheckAudioFileFormatRequest : NSObject<NSURLConnectionDelegate> {
    NSString *_url;
    NSURLConnection *_connection;
    FSAudioFileFormat _format;
    NSString *_contentType;
    BOOL _playlist;
}

@property (nonatomic,copy) NSString *url;
@property (copy) void (^onCompletion)();
@property (copy) void (^onFailure)();
@property (nonatomic,readonly) FSAudioFileFormat format;
@property (nonatomic,readonly) NSString *contentType;
@property (nonatomic,readonly) BOOL playlist;

- (void)start;
- (void)cancel;

@end