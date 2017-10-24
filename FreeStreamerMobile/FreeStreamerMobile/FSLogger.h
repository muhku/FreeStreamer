/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <Foundation/Foundation.h>

/**
 * A simple logger class.
 */
@interface FSLogger : NSObject {
    NSString *_baseDirectory;
    NSString *_logName;
    NSDateFormatter *_dateFormatter;
}

/**
 * Base directory.
 */
@property (nonatomic,strong) NSString *baseDirectory;
/**
 * Log name.
 */
@property (nonatomic,strong) NSString *logName;

/**
 * Checks if log directory exists.
 *
 * @param directory The directory to be checked.
 */
+ (BOOL)logDirectoryExists:(NSString *)directory;

/**
 * Logs a message with a timestamp.
 *
 * @param message The log message to be logged.
 */
- (void)logMessageWithTimestamp:(NSString *)message;
/**
 * Logs a message.
 *
 * @param message The log message to be logged.
 */
- (void)logMessage:(NSString *)message;

@end
