/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import "FSPlaylistItem.h"

@implementation FSPlaylistItem

- (NSURL *)nsURL
{
    if (self.url) {
        return [NSURL URLWithString:self.url];
    }
    if (self.originatingUrl) {
        return [NSURL URLWithString:self.originatingUrl];
    }
    return nil;
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