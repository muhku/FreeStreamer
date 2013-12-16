/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

/**
 * A playlist item. Each item has a title and url.
 */
@interface FSPlaylistItem : NSObject {
    NSString *_title;
    NSString *_url;
}

/**
 * The title of the playlist.
 */
@property (nonatomic,copy) NSString *title;
/**
 * The URL of the playlist.
 */
@property (nonatomic,copy) NSString *url;
/**
 * The NSURL of the playlist.
 */
@property (weak, readonly) NSURL *nsURL;

@end