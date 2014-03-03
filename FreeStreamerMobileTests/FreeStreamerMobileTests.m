/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#import <XCTest/XCTest.h>
#import "FSAudioStream.h"

@interface FreeStreamerMobileTests : XCTestCase {
    FSAudioStream *_stream;
    BOOL _keepRunning;
    BOOL _checkStreamState;
}

@end

@implementation FreeStreamerMobileTests

- (void)setUp
{
    [super setUp];
    
    // Put setup code here. This method is called before the invocation of each test method in the class.
    
    _stream = [[FSAudioStream alloc] init];
    _keepRunning = YES;
    _checkStreamState = NO;
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    
    [_stream stop];
    _keepRunning = NO;
    _checkStreamState = NO;
    
    [super tearDown];
}

- (void)testFileLength
{
    [[NSNotificationCenter defaultCenter] addObserverForName:FSAudioStreamStateChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *notification) {
                        
        NSLog(@"FSAudioStreamStateChangeNotification received!");
                        
        int state = [[notification.userInfo valueForKey:FSAudioStreamNotificationKey_State] intValue];
        
        if (state == kFsAudioStreamPlaying) {
            _checkStreamState = YES;
            
            // Set the stream silent, better for testing
            [_stream setVolume:0];
        }
    }];
    
    _stream.url = [NSURL URLWithString:@"http://www.tonycuffe.com/mp3/tail%20toddle.mp3"];
    [_stream play];
    
    NSTimeInterval timeout = 15.0;
    NSTimeInterval idle = 0.1;
    NSUInteger tickCounter = 0;
    BOOL timedOut = NO;
    
    NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        if (_checkStreamState) {
            if (tickCounter > 20) {
                NSLog(@"2 seconds passed since the stream started playing, checking the state");
            
                XCTAssertTrue((_stream.duration.minute == 1), @"Invalid stream duration (minutes)");
                XCTAssertTrue((_stream.duration.second == 28), @"Invalid stream duration (seconds)");
            
                // Checks done, we are done.
                _keepRunning = NO;
            
                goto done;
            } else {
                tickCounter++;
            }
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
    
done:
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:FSAudioStreamStateChangeNotification
                                                  object:nil];
}

@end