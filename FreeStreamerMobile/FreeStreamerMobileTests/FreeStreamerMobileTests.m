/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <XCTest/XCTest.h>
#import <FreeStreamer/FreeStreamer.h>

@interface FreeStreamerMobileTests : XCTestCase {
}

@property (nonatomic,strong) FSAudioStream *stream;
@property (nonatomic,strong) FSAudioController *controller;
@property (nonatomic,assign) BOOL keepRunning;
@property (nonatomic,assign) BOOL checkStreamState;
@property (nonatomic,assign) BOOL correctMetaDataReceived;
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

- (void)testPlaylistItemAddAndRemoval
{
    FSPlaylistItem *item1 = [[FSPlaylistItem alloc] init];
    item1.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
    
    FSPlaylistItem *item2 = [[FSPlaylistItem alloc] init];
    item2.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
    
    FSPlaylistItem *item3 = [[FSPlaylistItem alloc] init];
    item3.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
    
    FSPlaylistItem *item4 = [[FSPlaylistItem alloc] init];
    item4.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
    
    FSPlaylistItem *item5 = [[FSPlaylistItem alloc] init];
    item5.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
    
    [_controller addItem:item1];
    
    XCTAssertTrue(([_controller countOfItems] == 1), @"Invalid count of playlist items");
    
    [_controller addItem:item2];
    
    XCTAssertTrue(([_controller countOfItems] == 2), @"Invalid count of playlist items");
    
    [_controller addItem:item3];
    
    XCTAssertTrue(([_controller countOfItems] == 3), @"Invalid count of playlist items");
    
    [_controller addItem:item4];
    
    XCTAssertTrue(([_controller countOfItems] == 4), @"Invalid count of playlist items");
    
    [_controller addItem:item5];
    
    XCTAssertTrue(([_controller countOfItems] == 5), @"Invalid count of playlist items");
    
    [_controller playItemAtIndex:3]; // start playing item 4
    
    [_controller removeItemAtIndex:2]; // item 3 removed
    
    XCTAssertTrue(([_controller countOfItems] == 4), @"Invalid count of playlist items");
    
    XCTAssertTrue((_controller.currentPlaylistItem == item4), @"Item 4 not the current playback item");
    
    [_controller removeItemAtIndex:0]; // item 1 removed
    
    XCTAssertTrue((_controller.currentPlaylistItem == item4), @"Item 4 not the current playback item");
    
    XCTAssertTrue(([_controller countOfItems] == 3), @"Invalid count of playlist items");
    
    [_controller removeItemAtIndex:2]; // item 5 removed
    
    XCTAssertTrue((_controller.currentPlaylistItem == item4), @"Item 4 not the current playback item");
    
    XCTAssertTrue(([_controller countOfItems] == 2), @"Invalid count of playlist items");
    
    FSPlaylistItem *newItem = [[FSPlaylistItem alloc] init];
    newItem.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
    
    [_controller replaceItemAtIndex:0 withItem:newItem];
    
    XCTAssertTrue(([_controller countOfItems] == 2), @"Invalid count of playlist items");
    
    [_controller playItemAtIndex:0];
    
    XCTAssertTrue((_controller.currentPlaylistItem == newItem), @"newItem not the current playback item");
}

- (void)testPlaylistPlayback
{
    __weak FreeStreamerMobileTests *weakSelf = self;
    
    _controller.onStateChange = ^(FSAudioStreamState state) {
        NSLog(@"FSAudioStreamStateChangeNotification received!");
        
        if (state == kFsAudioStreamPlaying) {
            weakSelf.checkStreamState = YES;
        }
    };
    
    FSPlaylistItem *item1 = [[FSPlaylistItem alloc] init];
    item1.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
    
    NSMutableArray *playlistItems = [[NSMutableArray alloc] init];
    [playlistItems addObject:item1];
    
    [_controller playFromPlaylist:playlistItems];
    
    XCTAssertTrue(([_controller countOfItems] == 1), @"Invalid count of playlist items");
    
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
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testCacheDirectorySize
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *file = [documentsDirectory stringByAppendingPathComponent:@"FSCache-testing"];
    
    NSMutableData *data = [NSMutableData dataWithLength:12345];
    [data writeToFile:file atomically:YES];
    
    XCTAssertTrue(_stream.totalCachedObjectsSize == 12345, @"Invalid cache size");
    
    NSString *file2 = [documentsDirectory stringByAppendingPathComponent:@"FSCache-testing2"];
    
    NSMutableData *data2 = [NSMutableData dataWithLength:12345];
    [data2 writeToFile:file2 atomically:YES];
    
    XCTAssertTrue(_stream.totalCachedObjectsSize == 24690, @"Invalid cache size");
}

- (void)testLocalFilePlaybackTwice
{
    __weak FreeStreamerMobileTests *weakSelf = self;

    NSUInteger counter = 0;
    
playback_short_file:
    
    _stream = [[FSAudioStream alloc] init];
    
    _stream.volume = 0;
    
    _stream.onStateChange = ^(FSAudioStreamState state) {
        if (state == kFsAudioStreamPlaybackCompleted) {
            weakSelf.checkStreamState = YES;
        }
    };
    
    _stream.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test-2sec" ofType:@"mp3"]];
    [_stream play];
    
    NSTimeInterval timeout = 15.0;
    NSTimeInterval idle = 0.1;
    BOOL timedOut = NO;
    
    NSDate *timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        if (_checkStreamState) {
            // Stream finished
            
            counter++;
            
            if (counter == 2) {
                return;
            }
            
            _stream = nil;
            _checkStreamState = NO;
            
            goto playback_short_file;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
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

- (void)testSettingBufferSizes
{
    FSStreamConfiguration *config = [[FSStreamConfiguration alloc] init];
    config.usePrebufferSizeCalculationInSeconds = NO;
    config.requiredInitialPrebufferedByteCountForContinuousStream = 123456;
    
    FSAudioStream *stream = [_stream initWithConfiguration:config];
    
    XCTAssertTrue((stream.configuration.usePrebufferSizeCalculationInSeconds == NO), @"Invalid configuration value for usePrebufferSizeCalculationInSeconds");
    XCTAssertTrue((stream.configuration.requiredInitialPrebufferedByteCountForContinuousStream == 123456), @"Invalid configuration value for requiredInitialPrebufferedByteCountForContinuousStream");
    
    FSStreamConfiguration *config2 = [[FSStreamConfiguration alloc] init];
    config2.usePrebufferSizeCalculationInSeconds = YES;
    config2.requiredPrebufferSizeInSeconds = 1234;
    
    FSAudioStream *stream2 = [_stream initWithConfiguration:config2];
    
    XCTAssertTrue((stream2.configuration.usePrebufferSizeCalculationInSeconds == YES), @"Invalid configuration value for usePrebufferSizeCalculationInSeconds");
    XCTAssertTrue((stream2.configuration.requiredPrebufferSizeInSeconds == 1234), @"Invalid configuration value for requiredPrebufferSizeInSeconds");
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
    __weak FreeStreamerMobileTests *weakSelf = self;
    
    _controller.onStateChange = ^(FSAudioStreamState state) {
        NSLog(@"FSAudioStreamStateChangeNotification received!");
        
        if (state == kFsAudioStreamPlaying) {
            weakSelf.checkStreamState = YES;
        }
    };
    
    _controller.url = [NSURL URLWithString:@"http://somafm.com/groovesalad64.pls"];
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
            
            XCTAssertTrue((_controller.activeStream.continuous), @"Stream must be continuous");
            XCTAssertTrue((_controller.activeStream.contentLength == 0), @"Invalid content length");
            
            XCTAssertTrue((_controller.volume == 0), @"Invalid controller volume");
            
            XCTAssertTrue((_controller.activeStream.volume == 0), @"Invalid stream volume");
            
            XCTAssertTrue(([_controller.activeStream.contentType isEqualToString:@"audio/aacp"]), @"Invalid content type");
            XCTAssertTrue(([_controller.activeStream.suggestedFileExtension isEqualToString:@"aac"]), @"Invalid file extension");
            
            XCTAssertTrue((_controller.activeStream.prebufferedByteCount > 0), @"No cached bytes");
            
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
    offset.start = 238169;
    offset.end   = 510783;
    offset.position = 0.465815216;
    
    _stream.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp3"]];
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
            
            XCTAssertTrue((pos.minute == 0), @"Invalid seek minute");
            XCTAssertTrue((pos.second == 14), @"Invalid seek second");
            
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
    
    _controller.url = [NSURL URLWithString:@"http://somafm.com/groovesalad64.pls"];
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
            url = [NSURL URLWithString:@"https://archive.org/download/kahvi029/kahvi029a_badloop_lumme.mp3"];
        } else {
            url = [NSURL URLWithString:@"https://archive.org/download/kahvi029/kahvi029b_badloop_favorite_things.mp3"];
        }
        
        [_stream stop];
        
        [_stream playFromURL:url];
        
        NSLog(@"Cycle %lu", (unsigned long)++i);
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
    
    _stream.url = [NSURL URLWithString:@"https://archive.org/download/kahvi029/kahvi029a_badloop_lumme.mp3"];
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
                
                XCTAssertFalse((_stream.continuous), @"Stream must be non-continuous");
                
                XCTAssertTrue((_stream.duration.minute == 6), @"Invalid stream duration (minutes)");
                XCTAssertTrue((_stream.duration.second == 45), @"Invalid stream duration (seconds)");
                XCTAssertTrue((_stream.contentLength == 9720186), @"Invalid content length");
                
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
            XCTAssertTrue(([_controller.activeStream.contentType isEqualToString:@"audio/mpeg"]), @"Invalid content type");
            XCTAssertTrue(([_controller.activeStream.suggestedFileExtension isEqualToString:@"mp3"]), @"Invalid file extension");
            
            XCTAssertTrue((_controller.activeStream.duration.minute == 0), @"Invalid stream duration (minutes)");
            XCTAssertTrue((_controller.activeStream.duration.second == 31), @"Invalid stream duration (seconds)");
            
            XCTAssertTrue(([_controller.activeStream strictContentTypeChecking] == YES), @"strict content type setting should be active");
            
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
            XCTAssertTrue(([_controller.activeStream.contentType isEqualToString:@"audio/mpeg"]), @"Invalid content type");
            XCTAssertTrue(([_controller.activeStream.suggestedFileExtension isEqualToString:@"mp3"]), @"Invalid file extension");
            XCTAssertTrue((_controller.activeStream.contentLength == 33285), @"Invalid content length");
            
            XCTAssertTrue((_controller.activeStream.duration.minute == 0), @"Invalid stream duration (minutes)");
            XCTAssertTrue((_controller.activeStream.duration.second == 2), @"Invalid stream duration (seconds)");
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testMetaData
{
    __weak FreeStreamerMobileTests *weakSelf = self;
    
    self.correctMetaDataReceived = NO;
    
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
                                                      
                                                      NSString *artist = metaData[@"MPMediaItemPropertyArtist"];
                                                      
                                                      XCTAssertTrue([artist isEqualToString:@"Matias Muhonen"], @"Artist name does not match.");
                                                  }];
    
    _controller.onMetaDataAvailable = ^(NSDictionary *metaData) {
        NSString *artist = metaData[@"MPMediaItemPropertyArtist"];
        
        if ([artist isEqualToString:@"Matias Muhonen"]) {
            weakSelf.correctMetaDataReceived = YES;
        }
    };
    
    _controller.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp3"]];
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
                
                XCTAssertTrue((self.correctMetaDataReceived), @"Invalid meta data received");
                
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

- (void)testSeeking
{
    __weak FreeStreamerMobileTests *weakSelf = self;
    
    _stream.onStateChange = ^(FSAudioStreamState state) {
        switch (state) {
            case kFsAudioStreamRetrievingURL:
                NSLog(@"seek: kFsAudioStreamRetrievingURL");
                break;
            case kFsAudioStreamStopped:
                NSLog(@"seek: kFsAudioStreamStopped");
                break;
            case kFsAudioStreamBuffering:
                NSLog(@"seek: kFsAudioStreamBuffering");
                break;
            case kFsAudioStreamPlaying:
                NSLog(@"seek: kFsAudioStreamPlaying");
                weakSelf.checkStreamState = YES;
                break;
            case kFsAudioStreamPaused:
                NSLog(@"seek: kFsAudioStreamPaused");
                break;
            case kFsAudioStreamSeeking:
                NSLog(@"seek: kFsAudioStreamSeeking");
                break;
            case kFSAudioStreamEndOfFile:
                NSLog(@"seek: kFSAudioStreamEndOfFile");
                break;
            case kFsAudioStreamFailed:
                NSLog(@"seek: kFsAudioStreamFailed");
                break;
            case kFsAudioStreamRetryingStarted:
                NSLog(@"seek: kFsAudioStreamRetryingStarted");
                break;
            case kFsAudioStreamRetryingSucceeded:
                NSLog(@"seek: kFsAudioStreamRetryingSucceeded");
                break;
            case kFsAudioStreamRetryingFailed:
                NSLog(@"seek: kFsAudioStreamRetryingFailed");
                break;
            case kFsAudioStreamPlaybackCompleted:
                NSLog(@"seek: kFsAudioStreamPlaybackCompleted");
                break;
            case kFsAudioStreamUnknownState:
                NSLog(@"seek: kFsAudioStreamUnknownState");
                break;
                
            default:
                break;
        }
    };
    
    _stream.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp3"]];
    [_stream play];
    
    NSTimeInterval timeout = 15.0;
    NSTimeInterval idle = 0.1;
    BOOL timedOut;
    NSDate *timeoutDate;
    int loopCount = 1;
    NSUInteger tickCounter = 0;
    
wait_for_playing:
    
    tickCounter = 0;
    _checkStreamState = NO;
    
    NSLog(@"Seek try %i", loopCount);
    
    if (loopCount > 50) {
        // Done
        return;
    }
    
    timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        if (_checkStreamState) {
            if (tickCounter > 3) {
                NSLog(@"0.3 seconds passed since the stream started playing, checking the state");
                
                // Stream started playing.
                FSStreamPosition pos = {0};
                
                if (loopCount % 2 == 0) {
                    pos.position = 0.7;
                } else {
                    pos.position = 0.1;
                }
                
                [_stream seekToPosition:pos];
                
                loopCount++;
                
                goto wait_for_playing;
            } else {
                tickCounter++;
            }
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testPlaylistIteration
{
    __weak FreeStreamerMobileTests *weakSelf = self;
    
    const int playlistSize = 50;
    NSMutableArray *playlist = [[NSMutableArray alloc] init];
    
    for (int i=0; i < playlistSize; i++) {
        FSPlaylistItem *item = [[FSPlaylistItem alloc] init];
        item.url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp3"]];
        [playlist addObject:item];
    }
    
    _controller.onStateChange = ^(FSAudioStreamState state) {
        NSLog(@"FSAudioStreamStateChangeNotification received!");
        
        if (state == kFsAudioStreamPlaying) {
            weakSelf.checkStreamState = YES;
        }
    };
    
    [_controller playFromPlaylist:playlist];
    
    NSTimeInterval timeout = 15.0;
    NSTimeInterval idle = 0.1;
    BOOL timedOut;
    NSDate *timeoutDate;
    int loopCount = 1;
    NSUInteger tickCounter = 0;
    
wait_for_playing:
    
    tickCounter = 0;
    _checkStreamState = NO;
    
    NSLog(@"Playlist item try %i", loopCount);
    
    timedOut = NO;
    timeoutDate = [[NSDate alloc] initWithTimeIntervalSinceNow:timeout];
    while (!timedOut && _keepRunning) {
        NSDate *tick = [[NSDate alloc] initWithTimeIntervalSinceNow:idle];
        [[NSRunLoop currentRunLoop] runUntilDate:tick];
        timedOut = ([tick compare:timeoutDate] == NSOrderedDescending);
        
        if (_checkStreamState) {
            if (tickCounter > 3) {
                NSLog(@"0.3 seconds passed since the stream started playing, checking the state");
                
                if (![_controller hasNextItem]) {
                    XCTAssertTrue((loopCount == playlistSize), @"Last playlist item not reached");
                    return;
                }
                [_controller playNextItem];
                
                loopCount++;
                
                goto wait_for_playing;
            } else {
                tickCounter++;
            }
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}

- (void)testStrictContentTypeSetting
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
    _controller.configuration.requireStrictContentTypeChecking = NO;
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
            XCTAssertTrue(([_controller.activeStream strictContentTypeChecking] == NO), @"strict content type setting should not be active");
            
            return;
        }
    }
    XCTAssertFalse(timedOut, @"Timed out - the stream did not start playing");
}
 
@end
