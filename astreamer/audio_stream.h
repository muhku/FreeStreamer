/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#ifndef ASTREAMER_AUDIO_STREAM_H
#define ASTREAMER_AUDIO_STREAM_H

#import "http_stream.h"
#include "audio_queue.h"

#include <AudioToolbox/AudioToolbox.h>
#include <string>
#include <list>

namespace astreamer {
    
typedef struct queued_packet {
    AudioStreamPacketDescription desc;
    struct queued_packet *next;
    char data[];
} queued_packet_t;
    
enum Audio_Stream_Error {
    AS_ERR_OPEN = 1,          // Cannot open the audio stream
    AS_ERR_STREAM_PARSE = 2,  // Parse error
    AS_ERR_NETWORK = 3,        // Network error
    AS_ERR_UNSUPPORTED_FORMAT = 4
};
    
class Audio_Stream_Delegate;
class File_Output;
    
#define kAudioStreamBitrateBufferSize 50
	
class Audio_Stream : public HTTP_Stream_Delegate, public Audio_Queue_Delegate {    
public:
    Audio_Stream_Delegate *m_delegate;
    
    enum State {
        STOPPED,
        BUFFERING,
        PLAYING,
        SEEKING,
        FAILED,
        END_OF_FILE
    };
    
    Audio_Stream();
    virtual ~Audio_Stream();
    
    void open();
    void close();
    void pause();
    
    unsigned timePlayedInSeconds();
    unsigned durationInSeconds();
    void seekToTime(unsigned newSeekTime);
    
    void setVolume(float volume);
    
    void setUrl(CFURLRef url);
    void setStrictContentTypeChecking(bool strictChecking);
    void setDefaultContentType(std::string& defaultContentType);
    
    void setOutputFile(CFURLRef url);
    CFURLRef outputFile();
    
    State state();
    
    std::string contentType();
    
    /* Audio_Queue_Delegate */
    void audioQueueStateChanged(Audio_Queue::State state);
    void audioQueueBuffersEmpty();
    void audioQueueOverflow();
    void audioQueueUnderflow();
    void audioQueueInitializationFailed();
    
    /* HTTP_Stream_Delegate */
    void streamIsReadyRead();
    void streamHasBytesAvailable(UInt8 *data, UInt32 numBytes);
    void streamEndEncountered();
    void streamErrorOccurred();
    void streamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData);

private:
    
    Audio_Stream(const Audio_Stream&);
    Audio_Stream& operator=(const Audio_Stream&);
    
    bool m_httpStreamRunning;
    bool m_audioStreamParserRunning;
    bool m_needNewQueue;
    
    size_t m_contentLength;
    
    State m_state;
    HTTP_Stream *m_httpStream;
    Audio_Queue *m_audioQueue;
    
    AudioFileStreamID m_audioFileStream;	// the audio file stream parser
    AudioConverterRef m_audioConverter;
    AudioStreamBasicDescription m_srcFormat;
    AudioStreamBasicDescription m_dstFormat;
    
    UInt32 m_outputBufferSize;
    UInt8 *m_outputBuffer;
    
    UInt64 m_dataOffset;
    double m_seekTime;
    
    bool m_strictContentTypeChecking;
    std::string m_defaultContentType;
    std::string m_contentType;
    
    File_Output *m_fileOutput;
    
    CFURLRef m_outputFile;
    
    queued_packet_t *m_queuedHead;
    queued_packet_t *m_queuedTail;
    
    std::list <queued_packet_t*> m_processedPackets;
    
    UInt32 m_processedPacketsSizeTotal;  // global packet statistics: total size
    UInt32 m_processedPacketsCount;      // global packet statistics: count
    UInt64 m_audioDataByteCount;
    
    double m_packetDuration;
    double m_bitrateBuffer[kAudioStreamBitrateBufferSize];
    size_t m_bitrateBufferIndex;
    
    Audio_Queue *audioQueue();
    void closeAudioQueue();
    
    size_t contentLength();
    void closeAndSignalError(int error);
    void setState(State state);
    void setCookiesForStream(AudioFileStreamID inAudioFileStream);
    unsigned bitrate();
    
    static OSStatus encoderDataCallback(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData);
    static void propertyValueCallback(void *inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags);
    static void streamDataCallback(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions);
    
    AudioFileTypeID audioStreamTypeFromContentType(std::string contentType);    
};
    
class Audio_Stream_Delegate {
public:
    virtual void audioStreamStateChanged(Audio_Stream::State state) = 0;
    virtual void audioStreamErrorOccurred(int errorCode) = 0;
    virtual void audioStreamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData) = 0;
    virtual void samplesAvailable(AudioBufferList samples, AudioStreamPacketDescription description) = 0;
};    

} // namespace astreamer

#endif // ASTREAMER_AUDIO_STREAM_H