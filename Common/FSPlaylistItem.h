/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <Foundation/Foundation.h>

/**
 * A playlist item. Each item has a title and url.
 */
@interface FSPlaylistItem : NSObject {
}

/**
 * The title of the playlist item.
 */
@property (nonatomic,copy) NSString *title;
/**
 * The URL of the playlist item.
 */
@property (nonatomic,copy) NSString *url;
/**
 * The originating URL of the playlist item.
 */
@property (nonatomic,copy) NSString *originatingUrl;
/**
 * The NSURL of the playlist item.
 */
@property (weak, readonly) NSURL *nsURL;

@end