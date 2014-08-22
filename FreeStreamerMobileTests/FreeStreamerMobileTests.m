/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <XCTest/XCTest.h>
#import "FSAudioStream.h"
#import "FSAudioController.h"
#import "FSParsePlaylistRequest.h"

@interface FreeStreamerMobileTests : XCTestCase {
}

@property (nonatomic,strong) FSAudioStream *stream;
@property (nonatomic,strong) FSAudioController *controller;
@property (nonatomic,assign) BOOL keepRunning;
@property (nonatomic,assign) BOOL checkStreamState;
@property (nonatomic,strong) FSParsePlaylistRequest *playlistRequest;

@end

@implementation FreeStreamerMobileTests

- (void)setUp
{
    [super setUp];
    
    // Put setup code here. This method is called before the invocation of each test method in the class.
    
    _stream = [[FSAudioStream alloc] init];
    _controller = [[FSAudioController alloc] init];
    _keepRunning = YES;
    _checkStreamState = NO;
    
    [_stream setVolume:0];
    [_controller setVolume:0];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    
    _stream = nil;
    _controller = nil;
    _keepRunning = NO;
    _checkStreamState = NO;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:FSAudioStreamStateChangeNotification
                                                  object:nil];
    
    [super tearDown];
}

- (void)testPlaylistRetrieval
{
    __weak FreeStreamerMobileTests *weakSelf = self;
    
    _playlistRequest = [[FSParsePlaylistRequest alloc] init];
    _playlistRequest.onCompletion = ^() {
        weakSelf.keepRunning = NO;
    };
    _playlistRequest.onFailure = ^() {
        weakSelf.keepRunning = NO;
    };
    _playlistRequest.url = [NSURL URLWithString:@"http://www.radioswissclassic.ch/live/mp3.m3u"];
    
    [_playlistRequest start];
    
    NSTimeInterval timeout = 15.0;
    NSTimeInterval idle = 0.1;
    BOOL timedOut = NO;
    
    NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
    }
    
    if (!_keepRunning) {
        // Requests completed
        XCTAssertTrue(([_playlistRequest.playlistItems count] > 0), @"No playlist items");
        
        return;
    }
    
    XCTAssertFalse(timedOut, @"Timed out - failed to retrieve the playlist");
}

- (void)testSomaGrooveSaladPlays
{
    [[NSNotificationCenter defaultCenter] addObserverForName:FSAudioStreamStateChangeNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *notification) {
                                                      
                                                      NSLog(@"FSAudioStreamStateChangeNotification received!");
                                                      
                                                      int state = [[notification.userInfo valueForKey:FSAudioStreamNotificationKey_State] intValue];
                                                      
                                                      if (state == kFsAudioStreamPlaying) {
                                                          _checkStreamState = YES;
                                                      }
                                                  }];
    
    _controller.url = [NSURL URLWithString:@"http://somafm.com/groovesalad56.pls"];
    [_controller play];
    
    NSTimeInterval timeout = 15.0;
    NSTimeInterval idle = 0.1;
    BOOL timedOut = NO;
    
    NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        if (_checkStreamState) {
            // Stream started playing.
            XCTAssertTrue(([_controller.stream.contentType isEqualToString:@"audio/mpeg"]), @"Invalid content type");
            XCTAssertTrue(([_controller.stream.suggestedFileExtension isEqualToString:@"mp3"]), @"Invalid file extension");
            
            XCTAssertTrue((_controller.stream.prebufferedByteCount > 0), @"No cached bytes");
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testStreamPausing
{
    [[NSNotificationCenter defaultCenter] addObserverForName:FSAudioStreamStateChangeNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *notification) {
                                                      
                                                      NSLog(@"FSAudioStreamStateChangeNotification received!");
                                                      
                                                      int state = [[notification.userInfo valueForKey:FSAudioStreamNotificationKey_State] intValue];
                                                      
                                                      if (state == kFsAudioStreamPlaying) {
                                                          _checkStreamState = YES;
                                                          
                                                          XCTAssertTrue(([_controller isPlaying]), @"State must be playing when the player is not paused");
                                                      }
                                                      
                                                      if (state == kFsAudioStreamPaused) {
                                                          XCTAssertTrue((![_controller isPlaying]), @"State must not be playing when the player is paused");
                                                          
                                                          _keepRunning = NO;
                                                      }
                                                  }];
    
    _controller.url = [NSURL URLWithString:@"http://www.radioswissjazz.ch/live/mp3.m3u"];
    [_controller play];
    
    NSTimeInterval timeout = 15.0;
    NSTimeInterval idle = 0.1;
    BOOL timedOut = NO;
    
    NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        if (_checkStreamState) {
            // Stream started playing.
            
            [_controller pause];
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
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
                                                      }
                                                  }];
    
    _stream.url = [NSURL URLWithString:@"https://dl.dropboxusercontent.com/u/995250/FreeStreamer/As%20long%20as%20the%20stars%20shine.mp3"];
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
                
                XCTAssertTrue((_stream.duration.minute == 4), @"Invalid stream duration (minutes)");
                XCTAssertTrue((_stream.duration.second == 17), @"Invalid stream duration (seconds)");
                
                // Checks done, we are done.
                _keepRunning = NO;
                
                return;
            } else {
                tickCounter++;
            }
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testRadioHelsinkiPodcast
{
    [[NSNotificationCenter defaultCenter] addObserverForName:FSAudioStreamStateChangeNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *notification) {
                                                      
                                                      NSLog(@"FSAudioStreamStateChangeNotification received!");
                                                      
                                                      int state = [[notification.userInfo valueForKey:FSAudioStreamNotificationKey_State] intValue];
                                                      
                                                      if (state == kFsAudioStreamPlaying) {
                                                          _checkStreamState = YES;
                                                      }
                                                  }];
    
    _controller.url = [NSURL URLWithString:@"http://www.radiohelsinki.fi/feed/podcast/"];
    [_controller play];
    
    NSTimeInterval timeout = 15.0;
    NSTimeInterval idle = 0.1;
    BOOL timedOut = NO;
    
    NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        if (_checkStreamState) {
            // Stream started playing.
            XCTAssertTrue(([_controller.stream.contentType isEqualToString:@"audio/mpeg"]), @"Invalid content type");
            XCTAssertTrue(([_controller.stream.suggestedFileExtension isEqualToString:@"mp3"]), @"Invalid file extension");
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testMetaData
{
    [[NSNotificationCenter defaultCenter] addObserverForName:FSAudioStreamStateChangeNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *notification) {
                                                      
                                                      NSLog(@"FSAudioStreamStateChangeNotification received!");
                                                      
                                                      int state = [[notification.userInfo valueForKey:FSAudioStreamNotificationKey_State] intValue];
                                                      
                                                      if (state == kFsAudioStreamPlaying) {
                                                          _checkStreamState = YES;
                                                      }
                                                  }];
    
    
    [[NSNotificationCenter defaultCenter] addObserverForName:FSAudioStreamMetaDataNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *notification) {
                                                      
                                                      NSDictionary *dict = [notification userInfo];
                                                      NSDictionary *metaData = [dict valueForKey:FSAudioStreamNotificationKey_MetaData];
                                                      
                                                      NSLog(@"FSAudioStreamMetaDataNotification received!");
                                                      
                                                      NSString *stationName = metaData[@"IcecastStationName"];
                                                      
                                                      XCTAssertTrue([stationName isEqualToString:@"BBC 5Live"], @"Station name does not match.");
                                                  }];
    
    _controller.url = [NSURL URLWithString:@"http://www.bbc.co.uk/radio/listen/live/r5l_aaclca.pls"];
    [_controller play];
    
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
                
                // Checks done, we are done.
                _keepRunning = NO;
                
                return;
            } else {
                tickCounter++;
            }
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

@end