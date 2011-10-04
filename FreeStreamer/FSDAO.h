/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>

@interface FSDAO : NSObject {
    NSString *_data;
    NSMutableArray *_playlistItems;
}

- (void)parseData;
- (NSMutableArray *)playlistItems;

@end
