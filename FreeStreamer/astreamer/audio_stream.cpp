/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#include "audio_stream.h"

#include <pthread.h>

//#define AS_DEBUG 1

#if !defined (AS_DEBUG)
#define AS_TRACE(...) do {} while (0)
#else
#define AS_TRACE(...) printf(__VA_ARGS__)
#endif

namespace astreamer {
	
/* Create HTTP stream as Audio_Stream (this) as the delegate */
Audio_Stream::Audio_Stream(CFURLRef url) :
    m_delegate(0),
    m_httpStreamRunning(false),
    m_audioStreamParserRunning(false),
    m_state(STOPPED),
    m_httpStream(new HTTP_Stream(url, this)),
    m_audioQueue(new Audio_Queue())
{
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
        /* Already running */
        return;
    }
    
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
}
    
void Audio_Stream::pause()
{
    m_audioQueue->pause();
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
        closeAndSignalError(AS_ERR_OPEN);
        return;
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
	
void Audio_Stream::streamHasBytesAvailable(UInt8 *data, CFIndex numBytes)
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
    close();
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
    
void Audio_Stream::streamMetaDataAvailable(std::string metaData)
{
    if (m_delegate) {
        m_delegate->audioStreamMetaDataAvailable(metaData);
    }
}
    
/* private */

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
    
    THIS->m_audioQueue->handlePropertyChange(inAudioFileStream, inPropertyID, ioFlags);
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