Pod::Spec.new do |s|
	s.name                  = 'FreeStreamer'
	s.version               = '3.8.2'
	s.license               = 'BSD'
	s.summary               = 'A low-memory footprint streaming audio client for iOS and OS X.'
	s.homepage              = 'http://muhku.github.io/'
	s.author                = { 'Matias Muhonen' => 'mmu@iki.fi' }
	s.source                = { :git => 'https://github.com/muhku/FreeStreamer.git', :tag => s.version.to_s }
	s.ios.deployment_target = '6.0'
	s.osx.deployment_target = '10.7'
	s.source_files          = 'FreeStreamer/FreeStreamer/FSAudioController.h',
	                          'FreeStreamer/FreeStreamer/FSAudioController.m',
	                          'FreeStreamer/FreeStreamer/FSAudioStream.h',
	                          'FreeStreamer/FreeStreamer/FSAudioStream.mm',
	                          'FreeStreamer/FreeStreamer/FSCheckContentTypeRequest.h',
	                          'FreeStreamer/FreeStreamer/FSCheckContentTypeRequest.m',
	                          'FreeStreamer/FreeStreamer/FSParsePlaylistRequest.h',
	                          'FreeStreamer/FreeStreamer/FSParsePlaylistRequest.m',
	                          'FreeStreamer/FreeStreamer/FSParseRssPodcastFeedRequest.h',
	                          'FreeStreamer/FreeStreamer/FSParseRssPodcastFeedRequest.m',
	                          'FreeStreamer/FreeStreamer/FSPlaylistItem.h',
	                          'FreeStreamer/FreeStreamer/FSPlaylistItem.m',
	                          'FreeStreamer/FreeStreamer/FSXMLHttpRequest.h',
	                          'FreeStreamer/FreeStreamer/FSXMLHttpRequest.m',
	                          'FreeStreamer/FreeStreamer/audio_queue.cpp',
	                          'FreeStreamer/FreeStreamer/audio_queue.h',
	                          'FreeStreamer/FreeStreamer/audio_stream.cpp',
	                          'FreeStreamer/FreeStreamer/audio_stream.h',
	                          'FreeStreamer/FreeStreamer/caching_stream.cpp',
	                          'FreeStreamer/FreeStreamer/caching_stream.h',
	                          'FreeStreamer/FreeStreamer/file_output.cpp',
	                          'FreeStreamer/FreeStreamer/file_output.h',
	                          'FreeStreamer/FreeStreamer/file_stream.cpp',
	                          'FreeStreamer/FreeStreamer/file_stream.h',
	                          'FreeStreamer/FreeStreamer/http_stream.cpp',
	                          'FreeStreamer/FreeStreamer/http_stream.h',
	                          'FreeStreamer/FreeStreamer/id3_parser.cpp',
	                          'FreeStreamer/FreeStreamer/id3_parser.h',
	                          'FreeStreamer/FreeStreamer/input_stream.cpp',
	                          'FreeStreamer/FreeStreamer/input_stream.h',
	                          'FreeStreamer/FreeStreamer/stream_configuration.cpp',
	                          'FreeStreamer/FreeStreamer/stream_configuration.h'
	s.public_header_files   = 'FreeStreamer/FreeStreamer/FSAudioController.h',
	                          'FreeStreamer/FreeStreamer/FSAudioStream.h',
	                          'FreeStreamer/FreeStreamer/FSCheckContentTypeRequest.h',
	                          'FreeStreamer/FreeStreamer/FSParsePlaylistRequest.h',
	                          'FreeStreamer/FreeStreamer/FSParseRssPodcastFeedRequest.h',
	                          'FreeStreamer/FreeStreamer/FSPlaylistItem.h',
	                          'FreeStreamer/FreeStreamer/FSXMLHttpRequest.h'
	s.ios.frameworks        = 'CFNetwork', 'AudioToolbox', 'AVFoundation', 'MediaPlayer'
	s.osx.frameworks        = 'CFNetwork', 'AudioToolbox', 'AVFoundation'
	s.libraries	        = 'xml2', 'stdc++'
	s.xcconfig              = { 'HEADER_SEARCH_PATHS' => '$(SDKROOT)/usr/include/libxml2' }
	s.requires_arc          = true
        s.dependency 'Reachability', '~> 3.0'
end
