/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

@interface FSPlaylistItem : NSObject {
    NSString *_title;
    NSString *_url;
}

@property (nonatomic,copy) NSString *title;
@property (nonatomic,copy) NSString *url;
@property (weak, readonly) NSURL *nsURL;

@end
