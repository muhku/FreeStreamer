/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#include "audio_stream.h"

/*
 * Some servers may send an incorrect MIME type for the audio stream.
 * By uncommenting the following line, relaxed checks will be
 * performed for the MIME type. This allows playing more
 * streams:
 */
//#define AS_RELAX_CONTENT_TYPE_CHECK 1

//#define AS_DEBUG 1

#if !defined (AS_DEBUG)
#define AS_TRACE(...) do {} while (0)
#else
#define AS_TRACE(...) printf(__VA_ARGS__)
#endif

namespace astreamer {
	
/* Create HTTP stream as Audio_Stream (this) as the delegate */
Audio_Stream::Audio_Stream() :
    m_delegate(0),
    m_httpStreamRunning(false),
    m_audioStreamParserRunning(false),
    m_contentLength(0),
    m_state(STOPPED),
    m_httpStream(new HTTP_Stream()),
    m_audioQueue(new Audio_Queue()),
    m_dataOffset(0),
    m_seekTime(0),
#if defined (AS_RELAX_CONTENT_TYPE_CHECK)
    m_strictContentTypeChecking(false),
#else
    m_strictContentTypeChecking(true),
#endif
    m_defaultContentType("audio/mpeg")
{
    m_httpStream->m_delegate = this;
    m_audioQueue->m_delegate = this;
}

Audio_Stream::~Audio_Stream()
{
    close();
    
    m_httpStream->m_delegate = 0;
    delete m_httpStream, m_httpStream = 0;
    
    m_audioQueue->m_delegate = 0;
    delete m_audioQueue, m_audioQueue = 0;
}

void Audio_Stream::open()
{
    if (m_httpStreamRunning) {
        AS_TRACE("%s: already running: return\n", __PRETTY_FUNCTION__);
        return;
    }
    
    m_contentLength = 0;
    m_seekTime = 0;
    
    if (m_httpStream->open()) {
        AS_TRACE("%s: HTTP stream opened, buffering...\n", __PRETTY_FUNCTION__);
        m_httpStreamRunning = true;
        setState(BUFFERING);
    } else {
        AS_TRACE("%s: failed to open the HTTP stream\n", __PRETTY_FUNCTION__);
        setState(FAILED);
    }
}
    
void Audio_Stream::close()
{
    AS_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    /* Close the HTTP stream first so that the audio stream parser
       isn't fed with more data to parse */
    if (m_httpStreamRunning) {
        m_httpStream->close();
        m_httpStreamRunning = false;
    }
    
    if (m_audioStreamParserRunning) {
        if (AudioFileStreamClose(m_audioFileStream) != 0) {
            AS_TRACE("%s: AudioFileStreamClose failed\n", __PRETTY_FUNCTION__);
        }
        m_audioStreamParserRunning = false;
    }
    
    m_audioQueue->stop();
    m_dataOffset = 0;
    
    AS_TRACE("%s: leave\n", __PRETTY_FUNCTION__);
}
    
void Audio_Stream::pause()
{
    m_audioQueue->pause();
}
    
unsigned Audio_Stream::timePlayedInSeconds()
{
    return m_seekTime + m_audioQueue->timePlayedInSeconds();
}
    
unsigned Audio_Stream::durationInSeconds()
{
    unsigned duration = 0;
    unsigned bitrate = m_audioQueue->bitrate();
    
    if (bitrate == 0) {
        goto out;
    }
    
    duration = contentLength() / (bitrate * 0.125);
    
out:
    return duration;
}
    
void Audio_Stream::seekToTime(unsigned newSeekTime)
{
    unsigned duration = durationInSeconds();
    if (!(duration > 0)) {
        return;
    }
    
    close();
    
    setState(SEEKING);
    
    HTTP_Stream_Position position;
    double offset = (double)newSeekTime / (double)duration;
    position.start = m_dataOffset + offset * (contentLength() - m_dataOffset);
    position.end = contentLength();
    
    m_seekTime = newSeekTime;
    
    if (m_httpStream->open(position)) {
        AS_TRACE("%s: HTTP stream opened, buffering...\n", __PRETTY_FUNCTION__);
        m_httpStreamRunning = true;
    } else {
        AS_TRACE("%s: failed to open the HTTP stream\n", __PRETTY_FUNCTION__);
        setState(FAILED);
    }
}
    
void Audio_Stream::setUrl(CFURLRef url)
{
    m_httpStream->setUrl(url);
}
    
void Audio_Stream::setStrictContentTypeChecking(bool strictChecking)
{
    m_strictContentTypeChecking = strictChecking;
}

void Audio_Stream::setDefaultContentType(std::string& defaultContentType)
{
    m_defaultContentType = defaultContentType;
}
    
Audio_Stream::State Audio_Stream::state()
{
    return m_state;
}
    
AudioFileTypeID Audio_Stream::audioStreamTypeFromContentType(std::string contentType)
{
    AudioFileTypeID fileTypeHint = kAudioFileAAC_ADTSType;
    
    if (contentType.compare("") == 0) {
        AS_TRACE("***** Unable to detect the audio stream type: missing content-type! *****\n");
        goto out;
    }
    
    if (contentType.compare("audio/mpeg") == 0) {
        fileTypeHint = kAudioFileMP3Type;
        AS_TRACE("kAudioFileMP3Type detected\n");
    } else if (contentType.compare("audio/x-wav") == 0) {
        fileTypeHint = kAudioFileWAVEType;
        AS_TRACE("kAudioFileWAVEType detected\n");
    } else if (contentType.compare("audio/x-aifc") == 0) {
        fileTypeHint = kAudioFileAIFCType;
        AS_TRACE("kAudioFileAIFCType detected\n");
    } else if (contentType.compare("audio/x-aiff") == 0) {
        fileTypeHint = kAudioFileAIFFType;
        AS_TRACE("kAudioFileAIFFType detected\n");
    } else if (contentType.compare("audio/x-m4a") == 0) {
        fileTypeHint = kAudioFileM4AType;
        AS_TRACE("kAudioFileM4AType detected\n");
    } else if (contentType.compare("audio/mp4") == 0) {
        fileTypeHint = kAudioFileMPEG4Type;
        AS_TRACE("kAudioFileMPEG4Type detected\n");
    } else if (contentType.compare("audio/x-caf") == 0) {
        fileTypeHint = kAudioFileCAFType;
        AS_TRACE("kAudioFileCAFType detected\n");
    } else if (contentType.compare("audio/aac") == 0 ||
               contentType.compare("audio/aacp") == 0) {
        fileTypeHint = kAudioFileAAC_ADTSType;
        AS_TRACE("kAudioFileAAC_ADTSType detected\n");
    } else {
        AS_TRACE("***** Unable to detect the audio stream type from content-type %s *****\n", contentType.c_str());
    }
    
out:
    return fileTypeHint;        
}
    
void Audio_Stream::audioQueueStateChanged(Audio_Queue::State state)
{
    if (state == Audio_Queue::RUNNING) {
        setState(PLAYING);
    } else if (state == Audio_Queue::IDLE) {
        setState(STOPPED);
    }
}
    
void Audio_Stream::audioQueueBuffersEmpty()
{
    AS_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    if (m_httpStreamRunning) {
        /* Still feeding the audio queue with data,
           don't stop yet */
        return;
    }
    
    AS_TRACE("%s: closing the audio queue\n", __PRETTY_FUNCTION__);
    
    if (m_audioStreamParserRunning) {
        if (AudioFileStreamClose(m_audioFileStream) != 0) {
            AS_TRACE("%s: AudioFileStreamClose failed\n", __PRETTY_FUNCTION__);
        }
        m_audioStreamParserRunning = false;
    }
    
    // Keep the audio queue running until it has finished playing
    m_audioQueue->stop(false);
    
    AS_TRACE("%s: leave\n", __PRETTY_FUNCTION__);
}
    
void Audio_Stream::audioQueueOverflow()
{
    m_httpStream->setScheduledInRunLoop(false);
}
    
void Audio_Stream::audioQueueUnderflow()
{
    m_httpStream->setScheduledInRunLoop(true);
}
    
void Audio_Stream::audioQueueInitializationFailed()
{
    if (m_httpStreamRunning) {
        m_httpStream->close();
        m_httpStreamRunning = false;
    }
    
    setState(FAILED);
    
    if (m_delegate) {
        m_delegate->audioStreamErrorOccurred(AS_ERR_STREAM_PARSE);
    }
}
    
void Audio_Stream::streamIsReadyRead()
{
    if (m_audioStreamParserRunning) {
        AS_TRACE("%s: parser already running!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    /* Check if the stream's MIME type begins with audio/ */
    std::string contentType = m_httpStream->contentType();
    
    const char *audioContentType = "audio/";
    size_t audioContentTypeLength = strlen(audioContentType);
    
    if (contentType.compare(0, audioContentTypeLength, audioContentType) != 0) {
        if (m_strictContentTypeChecking) {
            closeAndSignalError(AS_ERR_OPEN);
            return;
        } else {
            contentType = m_defaultContentType;
        }
    }
    
    /* OK, it should be an audio stream, let's try to open it */
    OSStatus result = AudioFileStreamOpen(this,
                                          propertyValueCallback,
                                          streamDataCallback,
                                          audioStreamTypeFromContentType(contentType),
                                          &m_audioFileStream);
    
    if (result == 0) {
        AS_TRACE("%s: audio file stream opened.\n", __PRETTY_FUNCTION__);
        m_audioStreamParserRunning = true;
    } else {
        closeAndSignalError(AS_ERR_OPEN);
    }
}
	
void Audio_Stream::streamHasBytesAvailable(UInt8 *data, UInt32 numBytes)
{
    AS_TRACE("%s: %lu bytes\n", __FUNCTION__, numBytes);
    
    if (!m_httpStreamRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
	
    if (m_audioStreamParserRunning) {
        OSStatus result = AudioFileStreamParseBytes(m_audioFileStream, numBytes, data, 0);
        
        if (result != 0) {
            AS_TRACE("%s: AudioFileStreamParseBytes error %d\n", __PRETTY_FUNCTION__, (int)result);
            closeAndSignalError(AS_ERR_STREAM_PARSE);
        }
    }
}

void Audio_Stream::streamEndEncountered()
{
    AS_TRACE("%s\n", __PRETTY_FUNCTION__);
    
    if (!m_httpStreamRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    setState(END_OF_FILE);
    
    m_httpStream->close();
    m_httpStreamRunning = false;
    
    /*
     * When the audio playback is fine, the queue will signal
     * back that the playback has ended. However, if there was
     * a problem with the playback (a corrupted audio file for instance),
     * the queue will not signal back.
     */
    if (!m_audioQueue->initialized()) {
        closeAndSignalError(AS_ERR_STREAM_PARSE);
    }
}

void Audio_Stream::streamErrorOccurred()
{
    AS_TRACE("%s\n", __PRETTY_FUNCTION__);
    
    if (!m_httpStreamRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    closeAndSignalError(AS_ERR_NETWORK);
}
    
void Audio_Stream::streamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData)
{
    if (m_delegate) {
        m_delegate->audioStreamMetaDataAvailable(metaData);
    }
}
    
/* private */
    
size_t Audio_Stream::contentLength()
{
    if (m_contentLength == 0) {
        m_contentLength = m_httpStream->contentLength();
    }
    return m_contentLength;
}

void Audio_Stream::closeAndSignalError(int errorCode)
{
    AS_TRACE("%s: error %i\n", __PRETTY_FUNCTION__, errorCode);
    
    setState(FAILED);
    close();
    
    if (m_delegate) {
        m_delegate->audioStreamErrorOccurred(errorCode);
    }
}
    
void Audio_Stream::setState(State state)
{
    if (m_state == state) {
        return;
    }
    
    m_state = state;
    
    if (m_delegate) {
        m_delegate->audioStreamStateChanged(m_state);
    }
}
    
/* This is called by audio file stream parser when it finds property values */
void Audio_Stream::propertyValueCallback(void *inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
{
    AS_TRACE("%s\n", __PRETTY_FUNCTION__);
    Audio_Stream *THIS = static_cast<Audio_Stream*>(inClientData);
    
    if (!THIS->m_audioStreamParserRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    switch (inPropertyID) {
        case kAudioFileStreamProperty_DataOffset: {
            SInt64 offset;
            UInt32 offsetSize = sizeof(offset);
            OSStatus result = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataOffset, &offsetSize, &offset);
            if (result == 0) {
                THIS->m_dataOffset = offset;
            } else {
                AS_TRACE("%s: reading kAudioFileStreamProperty_DataOffset property failed\n", __PRETTY_FUNCTION__);
            }
            
            break;
        }
        default: {
            THIS->m_audioQueue->handlePropertyChange(inAudioFileStream, inPropertyID, ioFlags);
            break;
        }
    }
}

/* This is called by audio file stream parser when it finds packets of audio */
void Audio_Stream::streamDataCallback(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions)
{    
    AS_TRACE("%s: inNumberBytes %lu, inNumberPackets %lu\n", __FUNCTION__, inNumberBytes, inNumberPackets);
    Audio_Stream *THIS = static_cast<Audio_Stream*>(inClientData);
    
    if (!THIS->m_audioStreamParserRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    THIS->m_audioQueue->handleAudioPackets(inNumberBytes, inNumberPackets, inInputData, inPacketDescriptions);
}

} // namespace astreamer