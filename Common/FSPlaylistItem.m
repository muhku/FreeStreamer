/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
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

- (BOOL)isEqual:(id)anObject
{
    FSPlaylistItem *otherObject = anObject;
    
    if ([otherObject.title isEqual:self.title] &&
        [otherObject.url isEqual:self.url]) {
        return YES;
    }
    
    return NO;
}

@end