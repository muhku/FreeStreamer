/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#include "audio_stream.h"
#include "file_output.h"
#include "stream_configuration.h"
#include "http_stream.h"
#include "file_stream.h"
#include "caching_stream.h"

#include <CommonCrypto/CommonDigest.h>

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
    m_inputStreamRunning(false),
    m_audioStreamParserRunning(false),
    m_contentLength(0),
    m_state(STOPPED),
    m_inputStream(0),
    m_audioQueue(0),
    m_watchdogTimer(0),
    m_audioFileStream(0),
    m_audioConverter(0),
    m_initializationError(noErr),
    m_outputBufferSize(Stream_Configuration::configuration()->bufferSize),
    m_outputBuffer(new UInt8[m_outputBufferSize]),
    m_dataOffset(0),
    m_seekPosition(0),
    m_bounceCount(0),
    m_firstBufferingTime(0),
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
    m_cachedDataSize(0),
    m_processedPacketsCount(0),
    m_audioDataByteCount(0),
    m_packetDuration(0),
    m_bitrateBufferIndex(0),
    m_outputVolume(1.0),
    m_queueCanAcceptPackets(true),
    m_converterRunOutOfData(false)
{
    memset(&m_srcFormat, 0, sizeof m_srcFormat);
    
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
    
    if (m_inputStream) {
        m_inputStream->m_delegate = 0;
        delete m_inputStream, m_inputStream = 0;
    }
    
    if (m_audioConverter) {
        AudioConverterDispose(m_audioConverter), m_audioConverter = 0;
    }
    
    if (m_fileOutput) {
        delete m_fileOutput, m_fileOutput = 0;
    }
}
    
void Audio_Stream::open()
{
    open(0);
}

void Audio_Stream::open(Input_Stream_Position *position)
{
    if (m_inputStreamRunning || m_audioStreamParserRunning) {
        AS_TRACE("%s: already running: return\n", __PRETTY_FUNCTION__);
        return;
    }
    
    m_contentLength = 0;
    m_seekPosition = 0;
    m_bounceCount = 0;
    m_firstBufferingTime = 0;
    m_processedPacketsCount = 0;
    m_bitrateBufferIndex = 0;
    m_initializationError = noErr;
    m_converterRunOutOfData = false;
    
    if (m_watchdogTimer) {
        CFRunLoopTimerInvalidate(m_watchdogTimer);
        CFRelease(m_watchdogTimer), m_watchdogTimer = 0;
    }
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    if (m_contentType) {
        CFRelease(m_contentType), m_contentType = NULL;
    }
    
    bool success = false;
    
    if (position) {
        if (m_inputStream) {
            success = m_inputStream->open(*position);
        }
    } else {
        if (m_inputStream) {
            success = m_inputStream->open();
        }
    }
    
    if (success) {
        AS_TRACE("%s: HTTP stream opened, buffering...\n", __PRETTY_FUNCTION__);
        m_inputStreamRunning = true;
        setState(BUFFERING);
        
        if (config->startupWatchdogPeriod > 0) {
            /*
             * Start the WD if we have one requested. In this way we can track
             * that the stream doesn't stuck forever on the buffering state
             * (for instance some network error condition)
             */
            
            CFRunLoopTimerContext ctx = {0, this, NULL, NULL, NULL};
            
            m_watchdogTimer = CFRunLoopTimerCreate(NULL,
                                                   CFAbsoluteTimeGetCurrent() + config->startupWatchdogPeriod,
                                                   0,
                                                   0,
                                                   0,
                                                   watchdogTimerCallback,
                                                   &ctx);
            
            AS_TRACE("Starting the startup watchdog, period %i seconds\n", config->startupWatchdogPeriod);
            
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), m_watchdogTimer, kCFRunLoopCommonModes);
        }
    } else {
        AS_TRACE("%s: failed to open the HTTP stream\n", __PRETTY_FUNCTION__);
        closeAndSignalError(AS_ERR_OPEN);
    }
}
    
void Audio_Stream::close()
{
    AS_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    if (m_watchdogTimer) {
        CFRunLoopTimerInvalidate(m_watchdogTimer);
        CFRelease(m_watchdogTimer), m_watchdogTimer = 0;
    }
    
    /* Close the HTTP stream first so that the audio stream parser
       isn't fed with more data to parse */
    if (m_inputStreamRunning) {
        if (m_inputStream) {
            m_inputStream->close();
        }
        m_inputStreamRunning = false;
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
    
    if (FAILED != state()) {
        /*
         * Set the stream state to stopped if the stream was stopped successfully.
         * We don't want to cause a spurious stopped state as the fail state should
         * be the final state in case the stream failed.
         */
        setState(STOPPED);
    }
    
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
    m_cachedDataSize = 0;
    
    AS_TRACE("%s: leave\n", __PRETTY_FUNCTION__);
}
    
void Audio_Stream::pause()
{
    audioQueue()->pause();
}
    
unsigned Audio_Stream::timePlayedInSeconds()
{
    if (m_audioStreamParserRunning) {
        return m_seekPosition + audioQueue()->timePlayedInSeconds();
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
    if (state() == SEEKING) {
        return;
    } else {
        setState(SEEKING);
    }
    
    Input_Stream_Position position = streamPositionForTime(newSeekTime);
    
    if (position.start == 0 && position.end == 0) {
        return;
    }
    
    UInt64 originalContentLength = m_contentLength;
    
    close();
    
    AS_TRACE("Seeking position %llu\n", position.start);
    
    open(&position);
    
    setSeekPosition(newSeekTime);
    setContentLength(originalContentLength);
}
    
Input_Stream_Position Audio_Stream::streamPositionForTime(unsigned newSeekTime)
{
    Input_Stream_Position position;
    position.start = 0;
    position.end   = 0;
    
    unsigned duration = durationInSeconds();
    if (!(duration > 0)) {
        return position;
    }
    
    double offset = (double)newSeekTime / (double)duration;
    UInt64 seekByteOffset = m_dataOffset + offset * (contentLength() - m_dataOffset);
    
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
    
    return position;
}
    
void Audio_Stream::setVolume(float volume)
{
    if (volume < 0) {
        volume = 0;
    }
    if (volume > 1.0) {
        volume = 1.0;
    }
    // Store the volume so it will be used consequently when the queue plays
    m_outputVolume = volume;
    
    if (m_audioQueue) {
        m_audioQueue->setVolume(volume);
    }
}
    
void Audio_Stream::setPlayRate(float playRate)
{
    if (m_audioQueue) {
        m_audioQueue->setPlayRate(playRate);
    }
}
    
void Audio_Stream::setUrl(CFURLRef url)
{
    if (m_inputStream) {
        delete m_inputStream, m_inputStream = 0;
    }
    
    if (HTTP_Stream::canHandleUrl(url)) {
        Stream_Configuration *config = Stream_Configuration::configuration();
        
        if (config->cacheEnabled) {
            Caching_Stream *cache = new Caching_Stream(new HTTP_Stream());
            
            CFStringRef cacheIdentifier = createCacheIdentifierForURL(url);
            
            cache->setCacheIdentifier(cacheIdentifier);
            
            CFRelease(cacheIdentifier);
            
            m_inputStream = cache;
        } else {
            m_inputStream = new HTTP_Stream();
        }
        
        m_inputStream->m_delegate = this;
    } else if (File_Stream::canHandleUrl(url)) {
        m_inputStream = new File_Stream();
        m_inputStream->m_delegate = this;
    }
    
    if (m_inputStream) {
        m_inputStream->setUrl(url);
    }
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
    
void Audio_Stream::setSeekPosition(unsigned seekPosition)
{
    m_seekPosition = seekPosition;
}
    
void Audio_Stream::setContentLength(UInt64 contentLength)
{
    m_contentLength = contentLength;
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
    
CFStringRef Audio_Stream::sourceFormatDescription()
{
    unsigned char formatID[5];
    *(UInt32 *)formatID = OSSwapHostToBigInt32(m_srcFormat.mFormatID);
    
    formatID[4] = '\0';
    
    CFStringRef formatDescription = CFStringCreateWithFormat(NULL,
                                                            NULL,
                                                            CFSTR("formatID: %s, sample rate: %f"),
                                                            formatID,
                                                            m_srcFormat.mSampleRate);
    
    return formatDescription;
}

CFStringRef Audio_Stream::contentType()
{
    return m_contentType;
}
    
CFStringRef Audio_Stream::createCacheIdentifierForURL(CFURLRef url)
{
    CFStringRef urlString = CFURLGetString(url);
    CFStringRef urlHash = createHashForString(urlString);
    
    CFStringRef cacheIdentifier = CFStringCreateWithFormat(NULL, NULL, CFSTR("FSCache-%@"), urlHash);
    
    CFRelease(urlHash);
    
    return cacheIdentifier;
}
    
size_t Audio_Stream::cachedDataSize()
{
    return m_cachedDataSize;
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
    } else if (CFStringCompare(contentType, CFSTR("audio/mp4"), 0) == kCFCompareEqualTo ||
               CFStringCompare(contentType, CFSTR("video/mp4"), 0) == kCFCompareEqualTo) {
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
        
        float currentVolume = m_audioQueue->volume();
        
        if (currentVolume != m_outputVolume) {
            m_audioQueue->setVolume(m_outputVolume);
        }
    } else if (state == Audio_Queue::IDLE) {
        setState(STOPPED);
    } else if (state == Audio_Queue::PAUSED) {
        setState(PAUSED);
    }
}
    
void Audio_Stream::audioQueueBuffersEmpty()
{
    AS_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    if (m_inputStreamRunning && FAILED != state()) {
        /* Still feeding the audio queue with data,
           don't stop yet */
        setState(BUFFERING);
        
        if (m_firstBufferingTime == 0) {
            // Never buffered, just increase the counter
            m_firstBufferingTime = CFAbsoluteTimeGetCurrent();
            m_bounceCount++;
            
            AS_TRACE("stream buffered, increasing bounce count %zu, interval %i\n", m_bounceCount, config->bounceInterval);
        } else {
            // Buffered before, calculate the difference
            CFAbsoluteTime cur = CFAbsoluteTimeGetCurrent();
            
            int diff = cur - m_firstBufferingTime;
            
            if (diff >= config->bounceInterval) {
                // More than bounceInterval seconds passed from the last
                // buffering. So not a continuous bouncing. Reset the
                // counters.
                m_bounceCount = 0;
                m_firstBufferingTime = 0;
                
                AS_TRACE("%i seconds passed from last buffering, resetting counters, interval %i\n", diff, config->bounceInterval);
            } else {
                m_bounceCount++;
                
                AS_TRACE("%i seconds passed from last buffering, increasing bounce count to %zu, interval %i\n", diff, m_bounceCount, config->bounceInterval);
            }
        }
        
        // Check if we have reached the bounce state
        if (m_bounceCount >= config->maxBounceCount) {
            closeAndSignalError(AS_ERR_BOUNCING);
        }
        
        return;
    }
    
    // Keep enqueuing the packets in the queue until we have them
    
    int count = cachedDataCount();
    
    AS_TRACE("%i cached packets, enqueuing\n", count);
    
    if (count > 0) {
        enqueueCachedData(0);
    } else {
        AS_TRACE("%s: closing the audio queue\n", __PRETTY_FUNCTION__);
        
        close();
    }
}
    
void Audio_Stream::audioQueueOverflow()
{
    m_queueCanAcceptPackets = false;
}
    
void Audio_Stream::audioQueueUnderflow()
{
    m_queueCanAcceptPackets = true;
}
    
void Audio_Stream::audioQueueInitializationFailed()
{
    if (m_inputStreamRunning) {
        if (m_inputStream) {
            m_inputStream->close();
        }
        m_inputStreamRunning = false;
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
    
void Audio_Stream::audioQueueFinishedPlayingPacket()
{
    int count = cachedDataCount();
    
    if (count > 0) {
        enqueueCachedData(0);
    }
}
    
void Audio_Stream::streamIsReadyRead()
{
    if (m_audioStreamParserRunning) {
        AS_TRACE("%s: parser already running!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    CFStringRef audioContentType = CFSTR("audio/");
    CFStringRef videoContentType = CFSTR("video/");
    bool matchesAudioContentType = false;
    
    CFStringRef contentType = 0;
    
    if (m_inputStream) {
        contentType = m_inputStream->contentType();
    }
    
    if (m_contentType) {
        CFRelease(m_contentType), m_contentType = 0;
    }
    if (contentType) {
        m_contentType = CFStringCreateCopy(kCFAllocatorDefault, contentType);
        
        if (kCFCompareEqualTo == CFStringCompareWithOptions(contentType, audioContentType, CFRangeMake(0, CFStringGetLength(audioContentType)),0)) {
            matchesAudioContentType = true;
        } else if (kCFCompareEqualTo == CFStringCompareWithOptions(contentType, videoContentType, CFRangeMake(0, CFStringGetLength(videoContentType)),0)) {
            matchesAudioContentType = true;
        }
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
    
    if (!m_inputStreamRunning) {
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
            
            if (result == kAudioFileStreamError_NotOptimized) {
                AS_TRACE("Trying to use non-optimized format\n");
                closeAndSignalError(AS_ERR_UNSUPPORTED_FORMAT);
            } else {
                closeAndSignalError(AS_ERR_STREAM_PARSE);
            }
        } else if (m_initializationError == kAudioConverterErr_FormatNotSupported) {
            AS_TRACE("Audio stream initialization failed due to unsupported format\n");
            closeAndSignalError(AS_ERR_UNSUPPORTED_FORMAT);
        } else if (m_initializationError != noErr) {
            AS_TRACE("Audio stream initialization failed due to unknown error\n");
            closeAndSignalError(AS_ERR_OPEN);
        }
    }
}

void Audio_Stream::streamEndEncountered()
{
    AS_TRACE("%s\n", __PRETTY_FUNCTION__);
    
    if (!m_inputStreamRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    setState(END_OF_FILE);
    
    if (m_inputStream) {
        m_inputStream->close();
    }
    m_inputStreamRunning = false;
}

void Audio_Stream::streamErrorOccurred()
{
    AS_TRACE("%s\n", __PRETTY_FUNCTION__);
    
    if (!m_inputStreamRunning) {
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
    
CFStringRef Audio_Stream::createHashForString(CFStringRef str)
{
    UInt8 buf[4096];
    CFIndex usedBytes = 0;
    
    CFStringGetBytes(str,
                     CFRangeMake(0, CFStringGetLength(str)),
                     kCFStringEncodingUTF8,
                     '?',
                     false,
                     buf,
                     4096,
                     &usedBytes);
    
    CC_SHA1_CTX hashObject;
    CC_SHA1_Init(&hashObject);
    
    CC_SHA1_Update(&hashObject,
                   (const void *)buf,
                   (CC_LONG)usedBytes);
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &hashObject);
    
    char hash[2 * sizeof(digest) + 1];
    for (size_t i = 0; i < sizeof(digest); ++i) {
        snprintf(hash + (2 * i), 3, "%02x", (int)(digest[i]));
    }
    
    return CFStringCreateWithCString(kCFAllocatorDefault,
                                       (const char *)hash,
                                       kCFStringEncodingUTF8);
}
    
Audio_Queue* Audio_Stream::audioQueue()
{
    if (!m_audioQueue) {
        AS_TRACE("No audio queue, creating\n");
        
        m_audioQueue = new Audio_Queue();
        
        m_audioQueue->m_delegate = this;
        m_audioQueue->m_streamDesc = m_dstFormat;
        
        m_audioQueue->m_initialOutputVolume = m_outputVolume;
        
        m_queueCanAcceptPackets = true;
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
    
UInt64 Audio_Stream::contentLength()
{
    if (m_contentLength == 0) {
        if (m_inputStream) {
            m_contentLength = m_inputStream->contentLength();
        }
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
        AudioConverterSetProperty(m_audioConverter, kAudioConverterDecompressionMagicCookie, cookieSize, cookieData);
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
    
void Audio_Stream::watchdogTimerCallback(CFRunLoopTimerRef timer, void *info)
{
    Audio_Stream *THIS = (Audio_Stream *)info;
    
    if (PLAYING != THIS->state()) {
        AS_TRACE("The stream startup watchdog activated: stream didn't start to play soon enough\n");
        
        THIS->closeAndSignalError(AS_ERR_OPEN);
    }
}

int Audio_Stream::cachedDataCount()
{
    int count = 0;
    queued_packet_t *cur = m_queuedHead;
    while (cur) {
        cur = cur->next;
        count++;
    }
    return count;
}
    
void Audio_Stream::enqueueCachedData(int minPacketsRequired)
{
    if (!m_queueCanAcceptPackets) {
        AS_TRACE("Queue cannot accept packets, return\n");
        return;
    }
    
    if (m_converterRunOutOfData) {
        AS_TRACE("Converted run out of data\n");
        
        if (m_audioConverter) {
            AudioConverterDispose(m_audioConverter);
        }
        
        OSStatus err = AudioConverterNew(&(m_srcFormat),
                                         &(m_dstFormat),
                                         &(m_audioConverter));
        
        if (err) {
            AS_TRACE("Error in creating an audio converter, error %i\n", err);
            
           m_initializationError = err;
        }
        
        m_converterRunOutOfData = false;
    }
    
    if (state() == PAUSED) {
        return;
    }
    
    int count = cachedDataCount();
    
    if (count > minPacketsRequired) {
        AudioBufferList outputBufferList;
        outputBufferList.mNumberBuffers = 1;
        outputBufferList.mBuffers[0].mNumberChannels = m_dstFormat.mChannelsPerFrame;
        outputBufferList.mBuffers[0].mDataByteSize = m_outputBufferSize;
        outputBufferList.mBuffers[0].mData = m_outputBuffer;
        
        AudioStreamPacketDescription description;
        description.mStartOffset = 0;
        description.mDataByteSize = m_outputBufferSize;
        description.mVariableFramesInPacket = 0;
        
        UInt32 ioOutputDataPackets = m_outputBufferSize / m_dstFormat.mBytesPerPacket;
        
        AS_TRACE("calling AudioConverterFillComplexBuffer\n");
        
        Stream_Configuration *config = Stream_Configuration::configuration();
        
        OSStatus err = AudioConverterFillComplexBuffer(m_audioConverter,
                                                       &encoderDataCallback,
                                                       this,
                                                       &ioOutputDataPackets,
                                                       &outputBufferList,
                                                       NULL);
        if (err == noErr) {
            AS_TRACE("%i output bytes available for the audio queue\n", (unsigned int)ioOutputDataPackets);
            
            if (m_watchdogTimer) {
                AS_TRACE("The stream started to play, canceling the watchdog\n");
                
                CFRunLoopTimerInvalidate(m_watchdogTimer);
                CFRelease(m_watchdogTimer), m_watchdogTimer = 0;
            }
            
            setState(PLAYING);
            
            audioQueue()->handleAudioPackets(outputBufferList.mBuffers[0].mDataByteSize,
                                                   outputBufferList.mNumberBuffers,
                                                   outputBufferList.mBuffers[0].mData,
                                                   &description);
            
            if (m_delegate) {
                m_delegate->samplesAvailable(outputBufferList, description);
            }
            
            for(std::list<queued_packet_t*>::iterator iter = m_processedPackets.begin();
                iter != m_processedPackets.end(); iter++) {
                queued_packet_t *cur = *iter;
                
                m_cachedDataSize -= cur->desc.mDataByteSize;
                
                if (m_cachedDataSize < config->maxPrebufferedByteCount) {
                    AS_TRACE("Cache underflow, enabling the HTTP stream\n");
                    
                    if (m_inputStream) {
                        m_inputStream->setScheduledInRunLoop(true);
                    }
                }
                
                free(cur);
            }
            m_processedPackets.clear();
        } else {
            AS_TRACE("AudioConverterFillComplexBuffer failed, error %i\n", err);
        }
    } else {
        AS_TRACE("Less than %i packets queued, returning...\n", minPacketsRequired);
    }
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
        
        THIS->m_converterRunOutOfData = true;
        
        *ioNumberDataPackets = 0;
        
        ioData->mBuffers[0].mDataByteSize = 0;
        
        return noErr;
    } else {
        THIS->m_converterRunOutOfData = false;
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
            memset(&(THIS->m_srcFormat), 0, sizeof THIS->m_srcFormat);
            UInt32 asbdSize = sizeof(THIS->m_srcFormat);
            UInt32 formatListSize = 0;
            Boolean writable;
            OSStatus err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &(THIS->m_srcFormat));
            if (err) {
                AS_TRACE("Unable to set the src format\n");
                break;
            }

            if (!AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, &writable)) {
                void *formatListData = calloc(1, formatListSize);
                if (!AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, formatListData)) {
                    for (int i=0; i < formatListSize; i += sizeof(AudioFormatListItem)) {
                        AudioStreamBasicDescription *pasbd = (AudioStreamBasicDescription *)formatListData + i;
                        
                        if (pasbd->mFormatID == kAudioFormatMPEG4AAC_HE ||
                            pasbd->mFormatID == kAudioFormatMPEG4AAC_HE_V2) {
                            THIS->m_srcFormat = *pasbd;
                            break;
                        }
                    }
                }
                
                free(formatListData);
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
                AS_TRACE("Error in creating an audio converter, error %i\n", err);
                
                THIS->m_initializationError = err;
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
    
    Stream_Configuration *config = Stream_Configuration::configuration();
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
        
        THIS->m_cachedDataSize += size;
        
        if (THIS->m_cachedDataSize >= config->maxPrebufferedByteCount) {
            AS_TRACE("Cache overflow, disabling the HTTP stream\n");
            
            if (THIS->m_inputStream) {
                THIS->m_inputStream->setScheduledInRunLoop(false);
            }
        }
    }
    
    THIS->enqueueCachedData(config->decodeQueueSize);
}

} // namespace astreamer