/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2016 Matias Muhonen <mmu@iki.fi> 穆马帝
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
@property (nonatomic,copy) NSURL *url;
/**
 * The originating URL of the playlist item.
 */
@property (nonatomic,copy) NSURL *originatingUrl;
/**
 * The audio bytes if you know beforehand
 */
@property (nonatomic,assign) long audioBytes;
/**
 * The position to play from when play called. [0, 1]
 * WARN: might be wrong if audioBytes is incorrect
 */
@property (nonatomic,assign) float playFromPosition;

@end
