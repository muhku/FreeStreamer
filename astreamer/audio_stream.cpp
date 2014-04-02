/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#include "audio_stream.h"
#include "file_output.h"
#include "stream_configuration.h"

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
    m_needNewQueue(false),
    m_contentLength(0),
    m_state(STOPPED),
    m_httpStream(new HTTP_Stream()),
    m_audioQueue(0),
    m_audioFileStream(0),
    m_audioConverter(0),
    m_outputBufferSize(Stream_Configuration::configuration()->bufferSize),
    m_outputBuffer(new UInt8[m_outputBufferSize]),
    m_dataOffset(0),
    m_seekTime(0),
#if defined (AS_RELAX_CONTENT_TYPE_CHECK)
    m_strictContentTypeChecking(false),
#else
    m_strictContentTypeChecking(true),
#endif
    m_defaultContentType(CFSTR("audio/mpeg")),
    m_contentType(NULL),
    
    m_fileOutput(0),
    m_outputFile(NULL),
    m_queuedHead(0),
    m_queuedTail(0),
    m_processedPacketsCount(0),
    m_audioDataByteCount(0),
    m_packetDuration(0),
    m_bitrateBufferIndex(0)
{
    m_httpStream->m_delegate = this;
    
    memset(&m_dstFormat, 0, sizeof m_dstFormat);
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    m_dstFormat.mSampleRate = config->outputSampleRate;
    m_dstFormat.mFormatID = kAudioFormatLinearPCM;
    m_dstFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    m_dstFormat.mBytesPerPacket = 4;
    m_dstFormat.mFramesPerPacket = 1;
    m_dstFormat.mBytesPerFrame = 4;
    m_dstFormat.mChannelsPerFrame = 2;
    m_dstFormat.mBitsPerChannel = 16;
}

Audio_Stream::~Audio_Stream()
{
    if (m_defaultContentType) {
        CFRelease(m_defaultContentType), m_defaultContentType = NULL;
    }
    
    if (m_contentType) {
        CFRelease(m_contentType), m_contentType = NULL;
    }
    
    close();
    
    delete [] m_outputBuffer, m_outputBuffer = 0;
    
    m_httpStream->m_delegate = 0;
    delete m_httpStream, m_httpStream = 0;
    
    if (m_audioConverter) {
        AudioConverterDispose(m_audioConverter), m_audioConverter = 0;
    }
    
    if (m_fileOutput) {
        delete m_fileOutput, m_fileOutput = 0;
    }
}

void Audio_Stream::open()
{
    if (m_httpStreamRunning) {
        AS_TRACE("%s: already running: return\n", __PRETTY_FUNCTION__);
        return;
    }
    
    if (m_needNewQueue && m_audioQueue) {
        m_needNewQueue = false;
        
        closeAudioQueue();
    }
    
    m_contentLength = 0;
    m_seekTime = 0;
    m_processedPacketsCount = 0;
    m_bitrateBufferIndex = 0;
    
    if (m_contentType) {
        CFRelease(m_contentType), m_contentType = NULL;
    }
    
    if (m_httpStream->open()) {
        AS_TRACE("%s: HTTP stream opened, buffering...\n", __PRETTY_FUNCTION__);
        m_httpStreamRunning = true;
        setState(BUFFERING);
    } else {
        AS_TRACE("%s: failed to open the HTTP stream\n", __PRETTY_FUNCTION__);
        closeAndSignalError(AS_ERR_OPEN);
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
        if (m_audioFileStream) {
            if (AudioFileStreamClose(m_audioFileStream) != 0) {
                AS_TRACE("%s: AudioFileStreamClose failed\n", __PRETTY_FUNCTION__);
            }
            m_audioFileStream = 0;
        }
        m_audioStreamParserRunning = false;
    }
    
    closeAudioQueue();
    
    setState(STOPPED);
    
    /*
     * Free any remaining queud packets for encoding.
     */
    queued_packet_t *cur = m_queuedHead;
    while (cur) {
        queued_packet_t *tmp = cur->next;
        free(cur);
        cur = tmp;
    }
    m_queuedHead = m_queuedTail = 0;
    
    AS_TRACE("%s: leave\n", __PRETTY_FUNCTION__);
}
    
void Audio_Stream::pause()
{
    audioQueue()->pause();
}
    
unsigned Audio_Stream::timePlayedInSeconds()
{
    if (m_audioStreamParserRunning) {
        return m_seekTime + audioQueue()->timePlayedInSeconds();
    }
    return 0;
}
    
unsigned Audio_Stream::durationInSeconds()
{
    unsigned duration = 0;
    unsigned bitrate = this->bitrate();
    
    if (bitrate == 0) {
        goto out;
    }
    
    double d;
    
    if (m_audioDataByteCount > 0) {
        d = m_audioDataByteCount;
    } else {
        d = contentLength();
    }
    
    duration = d / (bitrate * 0.125);
    
out:
    return duration;
}
    
void Audio_Stream::seekToTime(unsigned newSeekTime)
{
    unsigned duration = durationInSeconds();
    if (!(duration > 0)) {
        return;
    }
    
    if (state() == SEEKING) {
        return;
    } else {
        setState(SEEKING);
    }
    
    m_seekTime = newSeekTime;
    
    double offset = (double)newSeekTime / (double)duration;
    UInt64 seekByteOffset = m_dataOffset + offset * (contentLength() - m_dataOffset);
    
    HTTP_Stream_Position position;

    position.start = seekByteOffset;
    position.end = contentLength();
    
    double packetDuration = m_srcFormat.mFramesPerPacket / m_srcFormat.mSampleRate;
    
    if (packetDuration > 0 && bitrate() > 0) {
        UInt32 ioFlags = 0;
        SInt64 packetAlignedByteOffset;
        SInt64 seekPacket = floor((double)newSeekTime / packetDuration);
        
        OSStatus err = AudioFileStreamSeek(m_audioFileStream, seekPacket, &packetAlignedByteOffset, &ioFlags);
        if (!err) {
            position.start = packetAlignedByteOffset + m_dataOffset;
        }
    }
    
    close();
    
    AS_TRACE("Seeking position %llu\n", position.start);
    
    if (m_httpStream->open(position)) {
        AS_TRACE("%s: HTTP stream opened, buffering...\n", __PRETTY_FUNCTION__);
        m_httpStreamRunning = true;
    } else {
        AS_TRACE("%s: failed to open the fHTTP stream\n", __PRETTY_FUNCTION__);
        setState(FAILED);
    }
}
    
void Audio_Stream::setVolume(float volume)
{
    if (m_audioQueue) {
        m_audioQueue->setVolume(volume);
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

void Audio_Stream::setDefaultContentType(CFStringRef defaultContentType)
{
    if (m_defaultContentType) {
        CFRelease(m_defaultContentType), m_defaultContentType = 0;
    }
    if (defaultContentType) {
        m_defaultContentType = CFStringCreateCopy(kCFAllocatorDefault, defaultContentType);
    }
}
    
void Audio_Stream::setOutputFile(CFURLRef url)
{
    if (m_fileOutput) {
        delete m_fileOutput, m_fileOutput = 0;
    }
    if (url) {
        m_fileOutput = new File_Output(url);
    }
    m_outputFile = url;
}
    
CFURLRef Audio_Stream::outputFile()
{
    return m_outputFile;
}
    
Audio_Stream::State Audio_Stream::state()
{
    return m_state;
}

CFStringRef Audio_Stream::contentType()
{
    return m_contentType;
}
    
AudioFileTypeID Audio_Stream::audioStreamTypeFromContentType(CFStringRef contentType)
{
    AudioFileTypeID fileTypeHint = kAudioFileMP3Type;
    
    if (!contentType) {
        AS_TRACE("***** Unable to detect the audio stream type: missing content-type! *****\n");
        goto out;
    }
    
    if (CFStringCompare(contentType, CFSTR("audio/mpeg"), 0) == kCFCompareEqualTo) {
        fileTypeHint = kAudioFileMP3Type;
        AS_TRACE("kAudioFileMP3Type detected\n");
    } else if (CFStringCompare(contentType, CFSTR("audio/x-wav"), 0) == kCFCompareEqualTo) {
        fileTypeHint = kAudioFileWAVEType;
        AS_TRACE("kAudioFileWAVEType detected\n");
    } else if (CFStringCompare(contentType, CFSTR("audio/x-aifc"), 0) == kCFCompareEqualTo) {
        fileTypeHint = kAudioFileAIFCType;
        AS_TRACE("kAudioFileAIFCType detected\n");
    } else if (CFStringCompare(contentType, CFSTR("audio/x-aiff"), 0) == kCFCompareEqualTo) {
        fileTypeHint = kAudioFileAIFFType;
        AS_TRACE("kAudioFileAIFFType detected\n");
    } else if (CFStringCompare(contentType, CFSTR("audio/x-m4a"), 0) == kCFCompareEqualTo) {
        fileTypeHint = kAudioFileM4AType;
        AS_TRACE("kAudioFileM4AType detected\n");
    } else if (CFStringCompare(contentType, CFSTR("audio/mp4"), 0) == kCFCompareEqualTo) {
        fileTypeHint = kAudioFileMPEG4Type;
        AS_TRACE("kAudioFileMPEG4Type detected\n");
    } else if (CFStringCompare(contentType, CFSTR("audio/x-caf"), 0) == kCFCompareEqualTo) {
        fileTypeHint = kAudioFileCAFType;
        AS_TRACE("kAudioFileCAFType detected\n");
    } else if (CFStringCompare(contentType, CFSTR("audio/aac"), 0) == kCFCompareEqualTo ||
               CFStringCompare(contentType, CFSTR("audio/aacp"), 0) == kCFCompareEqualTo) {
        fileTypeHint = kAudioFileAAC_ADTSType;
        AS_TRACE("kAudioFileAAC_ADTSType detected\n");
    } else {
        AS_TRACE("***** Unable to detect the audio stream type *****\n");
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
        setState(BUFFERING);
        
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
    audioQueue()->stop(false);
    m_needNewQueue = true;
    
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
        if (audioQueue()->m_lastError == kAudioFormatUnsupportedDataFormatError) {
            m_delegate->audioStreamErrorOccurred(AS_ERR_UNSUPPORTED_FORMAT);
        } else {
            m_delegate->audioStreamErrorOccurred(AS_ERR_STREAM_PARSE);
        }
    }
}
    
void Audio_Stream::streamIsReadyRead()
{
    if (m_audioStreamParserRunning) {
        AS_TRACE("%s: parser already running!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    CFStringRef audioContentType = CFSTR("audio/");
    const CFIndex audioContentTypeLength = CFStringGetLength(audioContentType);
    bool matchesAudioContentType = false;
    
    CFStringRef contentType = m_httpStream->contentType();
    
    if (m_contentType) {
        CFRelease(m_contentType), m_contentType = 0;
    }
    if (contentType) {
        m_contentType = CFStringCreateCopy(kCFAllocatorDefault, contentType);
    
        /* Check if the stream's MIME type begins with audio/ */
        matchesAudioContentType = (kCFCompareEqualTo ==
                                    CFStringCompareWithOptions(contentType, CFSTR("audio/"),
                                                               CFRangeMake(0, audioContentTypeLength),
                                                               0));
    }
    
    if (m_strictContentTypeChecking && !matchesAudioContentType) {
        closeAndSignalError(AS_ERR_OPEN);
        return;
    }
    
    m_audioDataByteCount = 0;
    
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
    AS_TRACE("%s: %u bytes\n", __FUNCTION__, (unsigned int)numBytes);
    
    if (!m_httpStreamRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    if (m_fileOutput) {
        m_fileOutput->write(data, numBytes);
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
    
Audio_Queue* Audio_Stream::audioQueue()
{
    if (!m_audioQueue) {
        AS_TRACE("No audio queue, creating\n");
        
        m_audioQueue = new Audio_Queue();
        
        m_audioQueue->m_delegate = this;
        m_audioQueue->m_streamDesc = m_dstFormat;
    }
    return m_audioQueue;
}
    
void Audio_Stream::closeAudioQueue()
{
    if (!m_audioQueue) {
        return;
    }
    
    AS_TRACE("Releasing audio queue\n");
    
    m_audioQueue->m_delegate = 0;
    delete m_audioQueue, m_audioQueue = 0;
}
    
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
    
void Audio_Stream::setCookiesForStream(AudioFileStreamID inAudioFileStream)
{
    OSStatus err;
    
    // get the cookie size
    UInt32 cookieSize;
    Boolean writable;
    
    err = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (err) {
        return;
    }
    
    // get the cookie data
    void* cookieData = calloc(1, cookieSize);
    err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (err) {
        free(cookieData);
        return;
    }
    
    // set the cookie on the queue.
    if (m_audioConverter) {
        err = AudioConverterSetProperty(m_audioConverter, kAudioConverterDecompressionMagicCookie, cookieSize, cookieData);
    }
    
    free(cookieData);
}
    
unsigned Audio_Stream::bitrate()
{
    if (m_processedPacketsCount < kAudioStreamBitrateBufferSize) {
        return 0;
    }
    double sum = 0;
    
    for (size_t i=0; i < kAudioStreamBitrateBufferSize; i++) {
        sum += m_bitrateBuffer[i];
    }
    
    return sum / kAudioStreamBitrateBufferSize;
}

OSStatus Audio_Stream::encoderDataCallback(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    Audio_Stream *THIS = (Audio_Stream *)inUserData;
    
    AS_TRACE("encoderDataCallback called\n");
    
    // Dequeue one packet per time for the decoder
    queued_packet_t *front = THIS->m_queuedHead;
    
    if (!front) {
        /*
         * End of stream - Inside your input procedure, you must set the total amount of packets read and the sizes of the data in the AudioBufferList to zero. The input procedure should also return noErr. This will signal the AudioConverter that you are out of data. More specifically, set ioNumberDataPackets and ioBufferList->mDataByteSize to zero in your input proc and return noErr. Where ioNumberDataPackets is the amount of data converted and ioBufferList->mDataByteSize is the size of the amount of data converted in each AudioBuffer within your input procedure callback. Your input procedure may be called a few more times; you should just keep returning zero and noErr.
         */
        
        AS_TRACE("run out of data to provide for encoding\n");
        
        *ioNumberDataPackets = 0;
        
        ioData->mBuffers[0].mDataByteSize = 0;
        
        return noErr;
    }
    
    *ioNumberDataPackets = 1;
    
    ioData->mBuffers[0].mData = front->data;
	ioData->mBuffers[0].mDataByteSize = front->desc.mDataByteSize;
	ioData->mBuffers[0].mNumberChannels = THIS->m_srcFormat.mChannelsPerFrame;
    
    if (outDataPacketDescription) {
        *outDataPacketDescription = &front->desc;
    }
    
    THIS->m_queuedHead = front->next;
    
    front->next = NULL;
    THIS->m_processedPackets.push_front(front);
    
    THIS->m_processedPacketsCount++;
    
    return noErr;
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
        case kAudioFileStreamProperty_AudioDataByteCount: {
            UInt32 byteCountSize = sizeof(UInt64);
            OSStatus err = AudioFileStreamGetProperty(inAudioFileStream,
                                                      kAudioFileStreamProperty_AudioDataByteCount,
                                                      &byteCountSize, &THIS->m_audioDataByteCount);
            if (err) {
                THIS->m_audioDataByteCount = 0;
            }
            break;
        }
        case kAudioFileStreamProperty_ReadyToProducePackets: {
            memset(&(THIS->m_srcFormat), 0, sizeof m_srcFormat);
            UInt32 asbdSize = sizeof(m_srcFormat);
            OSStatus err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &(THIS->m_srcFormat));
            if (err) {
                AS_TRACE("Unable to set the src format\n");
                break;
            }
            
            THIS->m_packetDuration = THIS->m_srcFormat.mFramesPerPacket / THIS->m_srcFormat.mSampleRate;
            
            AS_TRACE("srcFormat, bytes per packet %i\n", (unsigned int)THIS->m_srcFormat.mBytesPerPacket);
            
            if (THIS->m_audioConverter) {
                AudioConverterDispose(THIS->m_audioConverter);
            }
            
            err = AudioConverterNew(&(THIS->m_srcFormat),
                                    &(THIS->m_dstFormat),
                                    &(THIS->m_audioConverter));
            
            if (err) {
                AS_TRACE("Error in creating an audio converter\n");
            }
            
            THIS->setCookiesForStream(inAudioFileStream);
            
            THIS->audioQueue()->handlePropertyChange(inAudioFileStream, inPropertyID, ioFlags);
            break;
        }
        default: {
            THIS->audioQueue()->handlePropertyChange(inAudioFileStream, inPropertyID, ioFlags);
            break;
        }
    }
}

/* This is called by audio file stream parser when it finds packets of audio */
void Audio_Stream::streamDataCallback(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions)
{    
    AS_TRACE("%s: inNumberBytes %u, inNumberPackets %u\n", __FUNCTION__, inNumberBytes, inNumberPackets);
    Audio_Stream *THIS = static_cast<Audio_Stream*>(inClientData);
    
    if (!THIS->m_audioStreamParserRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    for (int i = 0; i < inNumberPackets; i++) {
        /* Allocate the packet */
        UInt32 size = inPacketDescriptions[i].mDataByteSize;
        queued_packet_t *packet = (queued_packet_t *)malloc(sizeof(queued_packet_t) + size);
        
        if (THIS->m_bitrateBufferIndex < kAudioStreamBitrateBufferSize) {
            // Only keep sampling for one buffer cycle; this is to keep the counters (for instance) duration
            // stable.
            
            THIS->m_bitrateBuffer[THIS->m_bitrateBufferIndex++] = 8 * inPacketDescriptions[i].mDataByteSize / THIS->m_packetDuration;
        }
        
        
        /* Prepare the packet */
        packet->next = NULL;
        packet->desc = inPacketDescriptions[i];
        packet->desc.mStartOffset = 0;
        memcpy(packet->data, (const char *)inInputData + inPacketDescriptions[i].mStartOffset,
               size);
        
        if (THIS->m_queuedHead == NULL) {
            THIS->m_queuedHead = THIS->m_queuedTail = packet;
        } else {
            THIS->m_queuedTail->next = packet;
            THIS->m_queuedTail = packet;
        }
    }
    
    int count = 0;
    queued_packet_t *cur = THIS->m_queuedHead;
    while (cur) {
        cur = cur->next;
        count++;
    }
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    if (count > config->decodeQueueSize) {
        THIS->setState(PLAYING);
        
        AudioBufferList outputBufferList;
        outputBufferList.mNumberBuffers = 1;
        outputBufferList.mBuffers[0].mNumberChannels = THIS->m_dstFormat.mChannelsPerFrame;
        outputBufferList.mBuffers[0].mDataByteSize = THIS->m_outputBufferSize;
        outputBufferList.mBuffers[0].mData = THIS->m_outputBuffer;
        
        AudioStreamPacketDescription description;
        description.mStartOffset = 0;
        description.mDataByteSize = THIS->m_outputBufferSize;
        description.mVariableFramesInPacket = 0;
        
        UInt32 ioOutputDataPackets = THIS->m_outputBufferSize / THIS->m_dstFormat.mBytesPerPacket;
        
        AS_TRACE("calling AudioConverterFillComplexBuffer\n");
        
        OSStatus err = AudioConverterFillComplexBuffer(THIS->m_audioConverter,
                                                       &encoderDataCallback,
                                                       THIS,
                                                       &ioOutputDataPackets,
                                                       &outputBufferList,
                                                       NULL);
        if (err == noErr) {
            AS_TRACE("%i output bytes available for the audio queue\n", (unsigned int)ioOutputDataPackets);
            
            THIS->audioQueue()->handleAudioPackets(outputBufferList.mBuffers[0].mDataByteSize,
                                                   outputBufferList.mNumberBuffers,
                                                   outputBufferList.mBuffers[0].mData,
                                                   &description);
            
            if (THIS->m_delegate) {
                THIS->m_delegate->samplesAvailable(outputBufferList, description);
            }
            
            for(std::list<queued_packet_t*>::iterator iter = THIS->m_processedPackets.begin();
                iter != THIS->m_processedPackets.end(); iter++) {
                queued_packet_t *cur = *iter;
                free(cur);
            }
            THIS->m_processedPackets.clear();
        }
    } else {
        AS_TRACE("Less than %i packets queued, returning...\n", config->decodeQueueSize);
    }
}

} // namespace astreamer