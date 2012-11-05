/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import "FSPlaylistItem.h"

@implementation FSPlaylistItem

@synthesize title=_title;
@synthesize url=_url;

- (id)init {
    self = [super init];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}


- (NSURL *)nsURL {
    return [NSURL URLWithString:_url];
}

@end
