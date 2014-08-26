/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSPlaylistItem.h"

@implementation FSPlaylistItem

- (NSURL *)nsURL
{
    if ([self.originatingUrl hasPrefix:@"file://"]) {
        // Resolve the local bundle URL
        NSString *path = [self.originatingUrl substringFromIndex:7];
        
        NSRange range = [path rangeOfString:@"." options:NSBackwardsSearch];
        
        NSString *fileName = [path substringWithRange:NSMakeRange(0, range.location)];
        NSString *suffix = [path substringWithRange:NSMakeRange(range.location + 1, [path length] - [fileName length] - 1)];
        
        return [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:fileName ofType:suffix]];
    }
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