FreeStreamer
====================

A streaming audio player for iOS and OS X.

Features
====================

- **CPU-friendly** design (uses 1% of CPU on average when streaming)
- **Multiple protocols supported**: ShoutCast, standard HTTP, local files
- **Prepared for tough network conditions**: adjustable buffer sizes, stream pre-buffering and restart on failures
- **Metadata support**: ShoutCast metadata, IDv2 tags
- **Local disk caching**: user only needs to stream a file once and after that it can be played from a local cache
- **Preloading**: playback can start immediately without needing to wait for buffering
- **Record**: support recording the stream contents to a file
- **Access the PCM audio samples**: as an example, a visualizer is included

Documentation
====================

See the [FAQ](https://github.com/muhku/FreeStreamer/wiki/FreeStreamer-FAQ) (Frequently Asked Questions) in the wiki. We also have an [API documentation](http://muhku.github.io/FreeStreamer/api/) available. The [usage instructions](https://github.com/muhku/FreeStreamer/wiki/Using-the-player-in-your-own-project) are also covered in the wiki.

Is somebody using this in real life?
====================

The short answer is yes! Check out our [website](http://muhku.github.io/FreeStreamer/) for the reference applications.

Reporting bugs and contributing
====================

For code contributions and other questions, it is preferrable to create a Github pull request. I don't have time for private email support, so usually the best way to get help is to interact with Github issues.

License
====================

The BSD license which the files are licensed under allows is as follows:

    Copyright (c) 2011-2016 Matias Muhonen <mmu@iki.fi> 穆马帝
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
