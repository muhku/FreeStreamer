/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#ifndef ASTREAMER_AUDIO_STREAM_H
#define ASTREAMER_AUDIO_STREAM_H

#import "http_stream.h"
#include "audio_queue.h"

#include <AudioToolbox/AudioToolbox.h>
#include <string>

namespace astreamer {
    
enum Audio_Stream_Error {
    AS_ERR_OPEN = 1,          // Cannot open the audio stream
    AS_ERR_STREAM_PARSE = 2,  // Parse error
    AS_ERR_NETWORK = 3        // Network error
};
    
class Audio_Stream_Delegate;
	
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
    
    void setUrl(CFURLRef url);
    void setStrictContentTypeChecking(bool strictChecking);
    void setDefaultContentType(std::string& defaultContentType);
    
    State state();
    
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
    
    size_t m_contentLength;
    
    State m_state;
    HTTP_Stream *m_httpStream;
    Audio_Queue *m_audioQueue;
    
    AudioFileStreamID m_audioFileStream;	// the audio file stream parser
    
    SInt64 m_dataOffset;
    unsigned m_seekTime;
    
    bool m_strictContentTypeChecking;
    std::string m_defaultContentType;
    
    size_t contentLength();
    void closeAndSignalError(int error);
    void setState(State state);
    
    static void propertyValueCallback(void *inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags);
    static void streamDataCallback(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions);
    
    AudioFileTypeID audioStreamTypeFromContentType(std::string contentType);    
};
    
class Audio_Stream_Delegate {
public:
    virtual void audioStreamStateChanged(Audio_Stream::State state) = 0;
    virtual void audioStreamErrorOccurred(int errorCode) = 0;
    virtual void audioStreamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData) = 0;
};    

} // namespace astreamer

#endif // ASTREAMER_AUDIO_STREAM_H