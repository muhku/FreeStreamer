[![Build Status](https://api.travis-ci.org/muhku/FreeStreamer.png?branch=master)](https://travis-ci.org/muhku/FreeStreamer)

Introduction
====================

FreeStreamer is an audio player engine for iOS and OS X, designed for playing audio streams. The engine has a minimal UI for demonstration. Respectfully, see the [FreeStreamerDesktop](https://github.com/muhku/FreeStreamer/tree/master/FreeStreamerDesktop) directory for OS X, and, [FreeStreamerMobile](https://github.com/muhku/FreeStreamer/tree/master/FreeStreamerMobile) for the iOS UI.

The engine is written in C++ and the FSAudioController Objective-C class wraps the implementation.

FreeStreamer has the following features:

- Fast and low memory footprint (no overhead of Objective-C method calls)
- Supports ShoutCast and IceCast audio streams + standard HTTP
- Can detect the stream type based on the content type
- Supports ShoutCast metadata
- Supports interruptions (for example a phone call during playing the stream)
- Supports backgrounding
- Supports a subset of the ID3v2 tag specification 
- Supports Podcast RSS feeds
- The stream contents can be stored in a file (see the OS X application for an example)
- It is possible to access the PCM audio samples (useful if you want your own audio analyzer, for instance)
- Includes a frequency analyzer and visualization, see [Additions](https://github.com/muhku/FreeStreamer/tree/master/Additions) and the iOS application

[![Player view](https://raw.github.com/muhku/FreeStreamer/master/Extra/player-new.png)](https://github.com/muhku/FreeStreamer/)

API documentation
====================

See [here](http://freestreamer.io/api/).

Using the player in your own project
====================

Please follow the following steps to use the player in your own project:

1. Make sure you have the following frameworks linked to your project:
   - _CFNetwork.framework_
   - _AudioToolbox.framework_
   - _AVFoundation.framework_
   - _libxml2.dylib_ (add ```$(SDKROOT)/usr/include/libxml2``` to the header search path, if not found)
   - _MediaPlayer.framework_ (iOS only)

2. Add the [Common](https://github.com/muhku/FreeStreamer/tree/master/Common) and [astreamer](https://github.com/muhku/FreeStreamer/tree/master/astreamer) directories to your project. Try building the project now and it should compile successfully.

3. **iOS only**: If you want to support background audio, add *App plays audio* to the target's *Required background modes*. You can find the property by clicking on the target on Xcode and opening the Info tab.

You can now stream an audio file like this. Declare the stream in your header file:

```
@class FSAudioStream;

@interface MyClass : NSObject {
    FSAudioStream *_audioStream;
}
```

Initialize and use the stream in your implementation:


```
#import "FSAudioStream.h"

_audioStream = [[FSAudioStream alloc] init];
[_audioStream playFromURL:[NSURL URLWithString:@"http://www.example.com/audio_file.mp3"]];
```

Note that FSAudioStream must exist during the playback of the stream. Do not declare the class as a local variable of a method or the stream will be deallocated and will not play.

Some servers may send an incorrect MIME type. In this case, FreeStreamer may not be able to play the stream. If you want to avoid the content-type checks (that the stream actually is an audio file), you can set the following property:

```
audioStream.strictContentTypeChecking = NO;
// Optionally, set the content-type where to fallback to
audioStream.defaultContentType = "audio/mpeg";
```

For streaming playlists, you need to use the [FSAudioController.h](https://github.com/muhku/FreeStreamer/blob/master/Common/FSAudioController.h) class. The class has some additional logic to resolve the playback URLs. Again, declare the class:

```
@class FSAudioController;

@interface MyClass : NSObject {
    FSAudioController *_audioController;
}
```

And use it:

```
#import "FSAudioStream.h"

_audioController = [[FSAudioController alloc] init];
_audioController.url = @"http://www.example.com/my_playlist.pls";
[_audioController play];
```

It is also possible to check the exact content of the stream by using the [FSCheckContentTypeRequest.h](https://github.com/muhku/FreeStreamer/blob/master/Common/FSCheckContentTypeRequest.h) and [FSParsePlaylistRequest.h](https://github.com/muhku/FreeStreamer/blob/master/Common/FSParsePlaylistRequest.h) classes:

```
FSCheckContentTypeRequest *request = [[FSCheckContentTypeRequest alloc] init];
request.url = @"http://www.example.com/not-sure-about-the-type-of-this-file";
request.onCompletion = ^() {
    if (self.request.playlist) {
        // The URL is a playlist; now do something with it...
	}
};
request.onFailure = ^() {	
};

[request start];
```

That's it! For more examples, please take a look at the example project. For instance, you may want to observe notifications on the audio stream state.

FAQ
====================

See [here](https://github.com/muhku/FreeStreamer/wiki/FreeStreamer-FAQ).

Debugging
====================

To enable debug logging, enable the following line in [astreamer/audio_stream.cpp](https://github.com/muhku/FreeStreamer/blob/master/astreamer/audio_stream.cpp#L17):

```
#define AS_DEBUG 1
```

After enabling the line, compile the code and run it.

It is also possible to check the _lastError_ property in the _FSAudioStream_ class:

```
NSLog(@"Last error code: %i", audioStream.lastError);
```

Or if you are using the _FSAudioController_ class, then:

```
NSLog(@"Last error code: %i", audioController.stream.lastError);
```

Reporting bugs and contributing
====================

For code contributions, please create a pull request in Github.

For bugs, please create a Github issue. I don't have time for private email support, so usually the best way to get help is to interact in Github.

License
====================

The BSD license which the files are licensed under allows is as follows:

    Copyright (c) 2011-2014 Matias Muhonen <info@freestreamer.io>
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
    3. The name of the author may not be used to endorse or promote products
       derived from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
    OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
    NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
    THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
