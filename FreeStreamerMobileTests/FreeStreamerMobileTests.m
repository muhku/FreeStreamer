/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2015 Matias Muhonen <mmu@iki.fi>
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
    
    _stream.volume = 0;
    _controller.volume = 0;
    
    [_stream expungeCache];
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

- (void)testStreamNullURL
{
    [_stream playFromURL:nil];
}

- (void)testControllerNullURL
{
    [_controller playFromURL:nil];
}

- (void)testNullCacheDirectory
{
    FSStreamConfiguration *config = [[FSStreamConfiguration alloc] init];
    config.cacheDirectory = nil;
    
    FSAudioStream *stream = [_stream initWithConfiguration:config];
    
    [stream play];
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
    _controller.stream.onStateChange = ^(FSAudioStreamState state) {
        NSLog(@"FSAudioStreamStateChangeNotification received!");
        
        if (state == kFsAudioStreamPlaying) {
            _checkStreamState = YES;
        }
    };
    
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
            
            XCTAssertTrue((_controller.volume == 0), @"Invalid controller volume");
            
            XCTAssertTrue((_controller.stream.volume == 0), @"Invalid stream volume");
            
            XCTAssertTrue(([_controller.stream.contentType isEqualToString:@"audio/mpeg"]), @"Invalid content type");
            XCTAssertTrue(([_controller.stream.suggestedFileExtension isEqualToString:@"mp3"]), @"Invalid file extension");
            
            XCTAssertTrue((_controller.stream.prebufferedByteCount > 0), @"No cached bytes");
            
            XCTAssertTrue(((unsigned)_controller.stream.bitRate == 56000), @"Invalid bit rate");
            
            XCTAssertTrue((_stream.totalCachedObjectsSize == 0), @"System has cached objects");
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testPlaybackFromOffset
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
    
    FSSeekByteOffset offset;
    offset.start = 4089672;
    offset.end   = 8227656;
    offset.position = 0.497128189;
    
    _stream.url = [NSURL URLWithString:@"https://dl.dropboxusercontent.com/u/995250/FreeStreamer/As%20long%20as%20the%20stars%20shine.mp3"];
    [_stream playFromOffset:offset];
    
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
            
            FSStreamPosition pos = _stream.currentTimePlayed;
            
            XCTAssertTrue((pos.minute == 2), @"Invalid seek minute");
            XCTAssertTrue((pos.second == 7), @"Invalid seek second");
            
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
            
            XCTAssertTrue((_stream.contentLength == 0), @"Invalid content length");
            
            [_controller pause];
            
            XCTAssertTrue((_stream.totalCachedObjectsSize == 0), @"System has cached objects");
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testStressHandling
{
    NSTimeInterval timeout = 10.0;
    NSTimeInterval idle = 0.7;
    BOOL timedOut = NO;
    
    NSUInteger i = 0;
    
    NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        NSURL *url;
        
        if (i % 2 == 0) {
            url = [NSURL URLWithString:@"https://dl.dropboxusercontent.com/u/995250/FreeStreamer/As%20long%20as%20the%20stars%20shine.mp3"];
        } else {
            url = [NSURL URLWithString:@"https://dl.dropboxusercontent.com/u/995250/FreeStreamer/5sec.mp3"];
        }
        
        [_stream stop];
        
        [_stream playFromURL:url];
        
        NSLog(@"Cycle %lu", ++i);
    }
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
                XCTAssertTrue((_stream.contentLength == 8227656), @"Invalid content length");
                
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

- (void)testShortFilePlayback
{
    __weak FreeStreamerMobileTests *weakSelf = self;
    
    _stream.url = [NSURL URLWithString:@"https://dl.dropboxusercontent.com/u/995250/FreeStreamer/5sec.mp3"];
    
    _stream.onCompletion = ^() {
        weakSelf.checkStreamState = YES;
    };
    
    [_stream play];
    
    NSTimeInterval timeout = 10.0;
    NSTimeInterval idle = 0.1;
    BOOL timedOut = NO;
    
    NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        if (_checkStreamState) {
            // Stream playback finished
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not complete playing");
}

- (void)testLocalFilePlayback
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
    
    _controller.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp3"]];
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
            
            XCTAssertTrue((_controller.stream.duration.minute == 0), @"Invalid stream duration (minutes)");
            XCTAssertTrue((_controller.stream.duration.second == 31), @"Invalid stream duration (seconds)");
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testShortLocalFilePlayback
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
    
    _controller.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
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
            XCTAssertTrue((_controller.stream.contentLength == 33285), @"Invalid content length");
            
            XCTAssertTrue((_controller.stream.duration.minute == 0), @"Invalid stream duration (minutes)");
            XCTAssertTrue((_controller.stream.duration.second == 2), @"Invalid stream duration (seconds)");
            
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
    
    _controller.stream.onMetaDataAvailable = ^(NSDictionary *metaData) {
        NSString *stationName = metaData[@"IcecastStationName"];
        
        XCTAssertTrue([stationName isEqualToString:@"BBC 5Live"], @"Station name does not match.");
    };
    
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
                
                XCTAssertTrue((_stream.totalCachedObjectsSize == 0), @"System has cached objects");
                
                return;
            } else {
                tickCounter++;
            }
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}
 
@end