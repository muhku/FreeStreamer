/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSLogger.h"

@interface FSLogger ()

+ (NSString *)applicationDocumentsDirectory;

@end

@implementation FSLogger

+ (NSString *)applicationDocumentsDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

- (void)setBaseDirectory:(NSString *)baseDirectory
{
    NSUInteger postfix = 0;
    NSString *directoryName = nil;
    
    do {
        postfix++;
        directoryName = [NSString stringWithFormat:@"%@-%lu", baseDirectory, (unsigned long)postfix];
    } while ([FSLogger logDirectoryExists:directoryName]);
    
    _baseDirectory = [NSString stringWithFormat:@"%@/%@", [FSLogger applicationDocumentsDirectory], directoryName];
}

- (NSString *)baseDirectory
{
    return _baseDirectory;
}

- (void)setLogName:(NSString *)logName
{
    _logName = [NSString stringWithFormat:@"%@/%@", self.baseDirectory, logName];
}

- (NSString *)logName
{
    return _logName;
}

+ (BOOL)logDirectoryExists:(NSString *)directory
{
    NSString *destinationDirectory = [NSString stringWithFormat:@"%@/%@", [FSLogger applicationDocumentsDirectory], directory];
    
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:destinationDirectory isDirectory:&isDir];
    
    return isDir;
}

- (void)logMessageWithTimestamp:(NSString *)message
{
    if (!_dateFormatter) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    }
    
    NSString *now = [_dateFormatter stringFromDate:[NSDate date]];
    
    [self logMessage:[NSString stringWithFormat:@"[%@] %@", now, message]];
}

- (void)logMessage:(NSString *)message
{
    if (![FSLogger logDirectoryExists:self.baseDirectory]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:self.baseDirectory
                                  withIntermediateDirectories:NO
                                                   attributes:nil
                                                        error:nil];
    }
    
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:self.logName];
    if (!fh ) {
        [[NSFileManager defaultManager] createFileAtPath:self.logName contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:self.logName];
    }
    
    if (!fh) {
        return;
    }
    
    NSString *logLineToWrite = [NSString stringWithFormat:@"%@\n", message];

    [fh seekToEndOfFile];
    [fh writeData:[logLineToWrite dataUsingEncoding:NSUTF8StringEncoding]];
    
    [fh closeFile];
}

@end
