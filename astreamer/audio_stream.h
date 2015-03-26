/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2015 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#ifndef ASTREAMER_AUDIO_STREAM_H
#define ASTREAMER_AUDIO_STREAM_H

#import "input_stream.h"
#include "audio_queue.h"

#include <AudioToolbox/AudioToolbox.h>
#include <list>

namespace astreamer {
    
typedef struct queued_packet {
    UInt64 identifier;
    AudioStreamPacketDescription desc;
    struct queued_packet *next;
    char data[];
} queued_packet_t;
    
typedef struct {
    float offset;
    float timePlayed;
} AS_Playback_Position;
    
enum Audio_Stream_Error {
    AS_ERR_OPEN = 1,          // Cannot open the audio stream
    AS_ERR_STREAM_PARSE = 2,  // Parse error
    AS_ERR_NETWORK = 3,        // Network error
    AS_ERR_UNSUPPORTED_FORMAT = 4,
    AS_ERR_BOUNCING = 5
};
    
class Audio_Stream_Delegate;
class File_Output;
    
#define kAudioStreamBitrateBufferSize 50
	
class Audio_Stream : public Input_Stream_Delegate, public Audio_Queue_Delegate {
public:
    Audio_Stream_Delegate *m_delegate;
    
    enum State {
        STOPPED,
        BUFFERING,
        PLAYING,
        PAUSED,
        SEEKING,
        FAILED,
        END_OF_FILE,
        PLAYBACK_COMPLETED
    };
    
    Audio_Stream();
    virtual ~Audio_Stream();
    
    void open();
    void open(Input_Stream_Position *position);
    void close(bool closeParser);
    void pause();
    void closeForNetworkDisconnectAndBufferEmpty();
    
    void startCachedDataPlayback();
    
    AS_Playback_Position playbackPosition();
    float durationInSeconds();
    void seekToOffset(float offset);
    
    Input_Stream_Position streamPositionForOffset(float offset);
    
    float currentVolume();
    void setVolume(float volume);
    void setPlayRate(float playRate);
    
    void setUrl(CFURLRef url);
    void setStrictContentTypeChecking(bool strictChecking);
    void setDefaultContentType(CFStringRef defaultContentType);
    void setSeekOffset(float offset);
    void setContentLength(UInt64 contentLength);
    void setPreloading(bool preloading);
    bool isPreloading();
    
    void setOutputFile(CFURLRef url);
    CFURLRef outputFile();
    
    State state();
    
    CFStringRef sourceFormatDescription();
    CFStringRef contentType();
    
    CFStringRef createCacheIdentifierForURL(CFURLRef url);
    
    size_t cachedDataSize();
    bool strictContentTypeChecking();
    float bitrate();
    
    UInt64 contentLength();
    int playbackDataCount();
    int audioQueueNumberOfBuffersInUse();
    int audioQueuePacketCount();
    
    /* Audio_Queue_Delegate */
    void audioQueueStateChanged(Audio_Queue::State state);
    void audioQueueBuffersEmpty();
    void audioQueueOverflow();
    void audioQueueUnderflow();
    void audioQueueInitializationFailed();
    void audioQueueFinishedPlayingPacket();
    
    /* Input_Stream_Delegate */
    void streamIsReadyRead();
    void streamHasBytesAvailable(UInt8 *data, UInt32 numBytes);
    void streamEndEncountered();
    void streamErrorOccurred(CFStringRef errorDesc);
    void streamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData);

private:
    
    Audio_Stream(const Audio_Stream&);
    Audio_Stream& operator=(const Audio_Stream&);
    
    bool m_inputStreamRunning;
    bool m_audioStreamParserRunning;
    bool m_initialBufferingCompleted;
    bool m_discontinuity;
    bool m_preloading;
    bool m_ignoreDecodeQueueSize;
    bool m_audioQueueConsumedPackets;
    
    UInt64 m_contentLength;
    UInt64 m_bytesReceived;
    
    State m_state;
    Input_Stream *m_inputStream;
    Audio_Queue *m_audioQueue;
    
    CFRunLoopTimerRef m_watchdogTimer;
    CFRunLoopTimerRef m_audioQueueTimer;
    
    AudioFileStreamID m_audioFileStream;	// the audio file stream parser
    AudioConverterRef m_audioConverter;
    AudioStreamBasicDescription m_srcFormat;
    AudioStreamBasicDescription m_dstFormat;
    OSStatus m_initializationError;
    
    UInt32 m_outputBufferSize;
    UInt8 *m_outputBuffer;
    
    UInt64 m_packetIdentifier;
    UInt64 m_dataOffset;
    float m_seekOffset;
    size_t m_bounceCount;
    CFAbsoluteTime m_firstBufferingTime;
    
    bool m_strictContentTypeChecking;
    CFStringRef m_defaultContentType;
    CFStringRef m_contentType;
    
    File_Output *m_fileOutput;
    
    CFURLRef m_outputFile;
    
    queued_packet_t *m_queuedHead;
    queued_packet_t *m_queuedTail;
    queued_packet_t *m_playPacket;
    
    std::list <queued_packet_t*> m_processedPackets;
    
    size_t m_cachedDataSize;
    
    UInt64 m_audioDataByteCount;
    UInt64 m_audioDataPacketCount;
    UInt32 m_bitRate;
    
    double m_packetDuration;
    double m_bitrateBuffer[kAudioStreamBitrateBufferSize];
    size_t m_bitrateBufferIndex;
    
    float m_outputVolume;
    
    bool m_queueCanAcceptPackets;
    bool m_converterRunOutOfData;
    
    CFStringRef createHashForString(CFStringRef str);
    
    Audio_Queue *audioQueue();
    void closeAudioQueue();
    
    void closeAndSignalError(int error, CFStringRef errorDescription);
    void setState(State state);
    void setCookiesForStream(AudioFileStreamID inAudioFileStream);
    
    int cachedDataCount();
    void enqueueCachedData(int minPacketsRequired);
    void cleanupCachedData();
    
    static void watchdogTimerCallback(CFRunLoopTimerRef timer, void *info);
    static void audioQueueTimerCallback(CFRunLoopTimerRef timer, void *info);
    
    static OSStatus encoderDataCallback(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData);
    static void propertyValueCallback(void *inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags);
    static void streamDataCallback(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions);
    
    AudioFileTypeID audioStreamTypeFromContentType(CFStringRef contentType);
};
    
class Audio_Stream_Delegate {
public:
    virtual void audioStreamStateChanged(Audio_Stream::State state) = 0;
    virtual void audioStreamErrorOccurred(int errorCode, CFStringRef errorDescription) = 0;
    virtual void audioStreamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData) = 0;
    virtual void samplesAvailable(AudioBufferList samples, AudioStreamPacketDescription description) = 0;
    virtual void audioStreamReceivedSize(UInt64 receivedSize) = 0;
    virtual void audioStreamBufferEmpty() = 0;
};    

} // namespace astreamer

#endif // ASTREAMER_AUDIO_STREAM_H