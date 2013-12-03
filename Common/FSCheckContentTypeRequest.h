/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

typedef enum {
    kFSFileFormatUnknown = 0,
    
    /* Playlist */
    kFSFileFormatM3UPlaylist,
    kFSFileFormatPLSPlaylist,
    
    /* Audio file */
    kFSFileFormatMP3,
    kFSFileFormatWAVE,
    kFSFileFormatAIFC,
    kFSFileFormatAIFF,
    kFSFileFormatM4A,
    kFSFileFormatMPEG4,
    kFSFileFormatCAF,
    kFSFileFormatAAC_ADTS,
    
    kFSFileFormatCount
} FSFileFormat;

@interface FSCheckContentTypeRequest : NSObject<NSURLConnectionDelegate> {
    NSString *_url;
    NSURLConnection *_connection;
    FSFileFormat _format;
    NSString *_contentType;
    BOOL _playlist;
}

@property (nonatomic,copy) NSString *url;
@property (copy) void (^onCompletion)();
@property (copy) void (^onFailure)();
@property (nonatomic,readonly) FSFileFormat format;
@property (nonatomic,readonly) NSString *contentType;
@property (nonatomic,readonly) BOOL playlist;

- (void)start;
- (void)cancel;

@end