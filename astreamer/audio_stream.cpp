/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2015 Matias Muhonen <mmu@iki.fi>
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
#include <pthread.h>
#define AS_TRACE(...) printf("[audio_stream.cpp:%i thread %x] ", __LINE__, pthread_mach_thread_np(pthread_self())); printf(__VA_ARGS__)
#endif

namespace astreamer {
    
static CFStringRef coreAudioErrorToCFString(CFStringRef basicErrorDescription, OSStatus error)
{
    char str[20] = {0};
    
    *(UInt32 *) (str + 1) = CFSwapInt32HostToBig(error);
    if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
        str[0] = str[5] = '\'';
        str[6] = '\0';
    } else {
        sprintf(str, "%d", (int)error);
    }
    
    CFStringRef formattedError = CFStringCreateWithFormat(NULL,
                                                          NULL,
                                                          CFSTR("%@: error code %s"),
                                                          basicErrorDescription,
                                                          str);
    return formattedError;
}
	
/* Create HTTP stream as Audio_Stream (this) as the delegate */
Audio_Stream::Audio_Stream() :
    m_delegate(0),
    m_inputStreamRunning(false),
    m_audioStreamParserRunning(false),
    m_initialBufferingCompleted(false),
    m_discontinuity(false),
    m_preloading(false),
    m_ignoreDecodeQueueSize(false),
    m_audioQueueConsumedPackets(false),
    m_contentLength(0),
    m_defaultContentLength(0),
    m_bytesReceived(0),
    m_state(STOPPED),
    m_inputStream(0),
    m_audioQueue(0),
    m_watchdogTimer(0),
    m_audioQueueTimer(0),
    m_audioFileStream(0),
    m_audioConverter(0),
    m_initializationError(noErr),
    m_outputBufferSize(Stream_Configuration::configuration()->bufferSize),
    m_outputBuffer(new UInt8[m_outputBufferSize]),
    m_packetIdentifier(0),
    m_dataOffset(0),
    m_seekOffset(0),
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
    m_playPacket(0),
    m_cachedDataSize(0),
    m_audioDataByteCount(0),
    m_audioDataPacketCount(0),
    m_bitRate(0),
    m_metaDataSizeInBytes(0),
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
    
    close(true);
    
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
    m_bytesReceived = 0;
    m_seekOffset = 0;
    m_bounceCount = 0;
    m_firstBufferingTime = 0;
    m_bitrateBufferIndex = 0;
    m_initializationError = noErr;
    m_converterRunOutOfData = false;
    m_audioDataPacketCount = 0;
    m_bitRate = 0;
    m_metaDataSizeInBytes = 0;
    m_discontinuity = true;
    m_ignoreDecodeQueueSize = false;
    m_audioQueueConsumedPackets = false;
    
    invalidateWatchdogTimer();
    
    if (m_audioQueueTimer) {
        CFRunLoopTimerInvalidate(m_audioQueueTimer);
        CFRelease(m_audioQueueTimer), m_audioQueueTimer = 0;
    }
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    if (m_contentType) {
        CFRelease(m_contentType), m_contentType = NULL;
    }
    
    bool success = false;
    
    if (position) {
        // Do not require buffering when seeking
        m_initialBufferingCompleted = true;
        
        if (m_inputStream) {
            success = m_inputStream->open(*position);
        }
    } else {
        m_initialBufferingCompleted = false;
        
        m_packetIdentifier = 0;
        
        if (m_inputStream) {
            success = m_inputStream->open();
        }
    }
    
    if (success) {
        AS_TRACE("%s: HTTP stream opened, buffering...\n", __PRETTY_FUNCTION__);
        m_inputStreamRunning = true;
        setState(BUFFERING);
        
        if (!m_preloading && config->startupWatchdogPeriod > 0) {
            createWatchdogTimer();
        }
    } else {
        closeAndSignalError(AS_ERR_OPEN, CFSTR("Input stream open error"));
    }
}
    
void Audio_Stream::close(bool closeParser)
{
    AS_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    invalidateWatchdogTimer();
    
    if (m_audioQueueTimer) {
        CFRunLoopTimerInvalidate(m_audioQueueTimer);
        CFRelease(m_audioQueueTimer), m_audioQueueTimer = 0;
    }
    
    /* Close the HTTP stream first so that the audio stream parser
       isn't fed with more data to parse */
    if (m_inputStreamRunning) {
        if (m_inputStream) {
            m_inputStream->close();
        }
        m_inputStreamRunning = false;
    }
    
    if (closeParser && m_audioStreamParserRunning) {
        if (m_audioFileStream) {
            if (AudioFileStreamClose(m_audioFileStream) != 0) {
                AS_TRACE("%s: AudioFileStreamClose failed\n", __PRETTY_FUNCTION__);
            }
            m_audioFileStream = 0;
        }
        m_audioStreamParserRunning = false;
    }
    
    closeAudioQueue();
    
    const State currentState = state();
    
    if (FAILED != currentState && SEEKING != currentState) {
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
    m_queuedHead = m_queuedTail = 0, m_playPacket = 0;
    m_cachedDataSize = 0;
    
    AS_TRACE("%s: leave\n", __PRETTY_FUNCTION__);
}
    
void Audio_Stream::pause()
{
    audioQueue()->pause();
}
    
void Audio_Stream::startCachedDataPlayback()
{
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    m_preloading = false;
    
    enqueueCachedData(config->decodeQueueSize);
}
    
AS_Playback_Position Audio_Stream::playbackPosition()
{
    AS_Playback_Position playbackPosition;
    playbackPosition.offset     = 0;
    playbackPosition.timePlayed = 0;
    
    if (m_audioStreamParserRunning) {
        AudioTimeStamp queueTime = audioQueue()->currentTime();
        
        playbackPosition.timePlayed = (durationInSeconds() * m_seekOffset) +
                                    (queueTime.mSampleTime / m_dstFormat.mSampleRate);
        
        float duration = durationInSeconds();
        
        if (duration > 0) {
            playbackPosition.offset = playbackPosition.timePlayed / durationInSeconds();
        }
    }
    return playbackPosition;
}
    
float Audio_Stream::durationInSeconds()
{
    if (m_audioDataPacketCount > 0 && m_srcFormat.mFramesPerPacket > 0) {
        return m_audioDataPacketCount * m_srcFormat.mFramesPerPacket / m_srcFormat.mSampleRate;
    }
    
    // Not enough data provided by the format, use bit rate based estimation
    UInt64 audioFileLength = 0;
    
    if (m_audioDataByteCount > 0) {
        audioFileLength = m_audioDataByteCount;
    } else {
        audioFileLength = contentLength() - m_metaDataSizeInBytes;
    }
    
    if (audioFileLength > 0) {
        float bitrate = this->bitrate();
        
        if (bitrate > 0) {
            return audioFileLength / (bitrate * 0.125);
        }
    }
    
    // No file length available, cannot calculate the duration
    return 0;
}
    
void Audio_Stream::seekToOffset(float offset)
{
    if (state() != PLAYING) {
        // Do not allow seeking if we are not currently playing the stream
        // This allows a previous seek to be completed
        return;
    }
    
    m_inputStream->setScheduledInRunLoop(false);
    
    // Close the audio queue so that it won't ask any more data
    closeAudioQueue();
    
    setState(SEEKING);
    
    Input_Stream_Position position = streamPositionForOffset(offset);
    
    if (position.start == 0 && position.end == 0) {
        closeAndSignalError(AS_ERR_NETWORK, CFSTR("Failed to retrieve seeking position"));
        return;
    }
    
    UInt64 originalContentLength = m_contentLength;
    
    const float duration = durationInSeconds();
    const double packetDuration = m_srcFormat.mFramesPerPacket / m_srcFormat.mSampleRate;
    
    if (packetDuration > 0) {
        UInt32 ioFlags = 0;
        SInt64 packetAlignedByteOffset;
        SInt64 seekPacket = floor((duration * offset) / packetDuration);
        
        m_packetIdentifier = seekPacket;
        
        OSStatus err = AudioFileStreamSeek(m_audioFileStream, seekPacket, &packetAlignedByteOffset, &ioFlags);
        if (!err) {
            position.start = packetAlignedByteOffset + m_dataOffset;
        } else {
            closeAndSignalError(AS_ERR_NETWORK, CFSTR("Failed to calculate seeking position"));
            return;
        }
    } else {
        closeAndSignalError(AS_ERR_NETWORK, CFSTR("Failed to calculate seeking position"));
        return;
    }
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    // Do a cache lookup if we can find the seeked packet from the cache and no need to
    // open the stream from the new position
    bool foundCachedPacket = false;
    queued_packet_t *seekPacket = 0;
    
    if (config->seekingFromCacheEnabled) {
        queued_packet_t *cur = m_queuedHead;
        while (cur) {
            if (cur->identifier == m_packetIdentifier) {
                foundCachedPacket = true;
                seekPacket = cur;
                break;
            }
            
            queued_packet_t *tmp = cur->next;
            cur = tmp;
        }
    } else {
        AS_TRACE("Seeking from cache disabled\n");
    }
    
    if (!foundCachedPacket) {
        AS_TRACE("Seeked packet not found from cache, reopening the input stream\n");
        
        // Close but keep the stream parser running
        close(false);
        
        m_bytesReceived = 0;
        m_bounceCount = 0;
        m_firstBufferingTime = 0;
        m_bitrateBufferIndex = 0;
        m_initializationError = noErr;
        m_converterRunOutOfData = false;
        m_discontinuity = true;

        bool success = m_inputStream->open(position);
        
        if (success) {
            setSeekOffset(offset);
            setContentLength(originalContentLength);
            
            m_inputStreamRunning = true;

        } else {
            closeAndSignalError(AS_ERR_OPEN, CFSTR("Input stream open error"));
            return;
        }
    } else {
        AS_TRACE("Seeked packet found from cache!\n");
        
        // Found the packet from the cache, let's use the cache directly.
        
        m_playPacket    = seekPacket;
        m_discontinuity = true;
        
        setSeekOffset(offset);
    }
    
    audioQueue()->init();
    
    setState(BUFFERING);
    
    m_inputStream->setScheduledInRunLoop(true);
}
    
Input_Stream_Position Audio_Stream::streamPositionForOffset(float offset)
{
    Input_Stream_Position position;
    position.start = 0;
    position.end   = 0;
    
    const float duration = durationInSeconds();
    if (!(duration > 0)) {
        return position;
    }
    
    UInt64 seekByteOffset = m_dataOffset + offset * (contentLength() - m_dataOffset);
    
    position.start = seekByteOffset;
    position.end = contentLength();
    
    return position;
}
    
float Audio_Stream::currentVolume()
{
    return m_outputVolume;
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
    
void Audio_Stream::setSeekOffset(float offset)
{
    m_seekOffset = offset;
}
 
void Audio_Stream::setDefaultContentLength(UInt64 defaultContentLength)
{
    m_defaultContentLength = defaultContentLength;
}
    
void Audio_Stream::setContentLength(UInt64 contentLength)
{
    m_contentLength = contentLength;
}
    
void Audio_Stream::setPreloading(bool preloading)
{
    m_preloading = preloading;
}
    
bool Audio_Stream::isPreloading()
{
    return m_preloading;
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
    
bool Audio_Stream::strictContentTypeChecking()
{
    return m_strictContentTypeChecking;
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
    
    /*
     * Entering here means that the audio queue has run out of data to play.
     */
    
    const int count = playbackDataCount();
    
    /*
     * If we don't have any cached data to play and we are still supposed to
     * feed the audio queue with data, enter the buffering state.
     */
    if (count == 0 && m_inputStreamRunning && FAILED != state()) {
        Stream_Configuration *config = Stream_Configuration::configuration();
        
        m_playPacket = m_queuedHead;
        
        // Always make sure we are scheduled to receive data if we start buffering
        m_inputStream->setScheduledInRunLoop(true);
        
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
            CFStringRef errorDescription = CFStringCreateWithFormat(NULL, NULL, CFSTR("Buffered %zu times in the last %i seconds"), m_bounceCount, config->maxBounceCount);
            
            closeAndSignalError(AS_ERR_BOUNCING, errorDescription);
            if (errorDescription) {
                CFRelease(errorDescription);
            }
        }
        
        // Create the watchdog in case the input stream gets stuck
        createWatchdogTimer();
        
        return;
    }
    
    AS_TRACE("%i cached packets, enqueuing\n", count);
    
    // Keep enqueuing the packets in the queue until we have them
    
    if (m_playPacket && count > 0) {
        enqueueCachedData(0);
    } else {
        AS_TRACE("%s: closing the audio queue\n", __PRETTY_FUNCTION__);
        
        setState(PLAYBACK_COMPLETED);
        
        close(true);
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
            m_delegate->audioStreamErrorOccurred(AS_ERR_UNSUPPORTED_FORMAT, CFSTR("Audio queue failed, unsupported format"));
        } else {
            CFStringRef errorDescription = coreAudioErrorToCFString(CFSTR("Audio queue failed"), audioQueue()->m_lastError);
            m_delegate->audioStreamErrorOccurred(AS_ERR_STREAM_PARSE, errorDescription);
            if (errorDescription) {
                CFRelease(errorDescription);
            }
        }
    }
}
    
void Audio_Stream::audioQueueFinishedPlayingPacket()
{
    int count = playbackDataCount();
    
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
        CFStringRef errorDescription = NULL;
        
        if (m_contentType) {
            errorDescription = CFStringCreateWithFormat(NULL, NULL, CFSTR("Strict content type checking active, %@ is not an audio content type"), m_contentType);
        } else {
            errorDescription = CFStringCreateCopy(kCFAllocatorDefault, CFSTR("Strict content type checking active, no content type provided by the server"));
        }
        
        closeAndSignalError(AS_ERR_OPEN, errorDescription);
        if (errorDescription) {
            CFRelease(errorDescription);
        }
        return;
    }
    
    m_audioDataByteCount = 0;
    
    /* OK, it should be an audio stream, let's try to open it */
    OSStatus result = AudioFileStreamOpen(this,
                                          propertyValueCallback,
                                          streamDataCallback,
                                          audioStreamTypeFromContentType((contentType ? contentType : m_defaultContentType)),
                                          &m_audioFileStream);
    
    if (result == 0) {
        AS_TRACE("%s: audio file stream opened.\n", __PRETTY_FUNCTION__);
        m_audioStreamParserRunning = true;
    } else {
        closeAndSignalError(AS_ERR_OPEN, CFSTR("Audio file stream parser open error"));
    }
}
	
void Audio_Stream::streamHasBytesAvailable(UInt8 *data, UInt32 numBytes)
{
    AS_TRACE("%s: %u bytes\n", __FUNCTION__, (unsigned int)numBytes);
    
    if (!m_inputStreamRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    m_bytesReceived += numBytes;
    
    if (m_fileOutput) {
        m_fileOutput->write(data, numBytes);
    }
	
    if (m_audioStreamParserRunning) {
        OSStatus result = AudioFileStreamParseBytes(m_audioFileStream, numBytes, data, (m_discontinuity ? kAudioFileStreamParseFlag_Discontinuity : 0));
        
        if (result != 0) {
            AS_TRACE("%s: AudioFileStreamParseBytes error %d\n", __PRETTY_FUNCTION__, (int)result);
            
            if (result == kAudioFileStreamError_NotOptimized) {
                closeAndSignalError(AS_ERR_UNSUPPORTED_FORMAT, CFSTR("Non-optimized formats not supported for streaming"));
            } else {
                CFStringRef errorDescription = coreAudioErrorToCFString(CFSTR("Audio file stream parse bytes error"), result);
                closeAndSignalError(AS_ERR_STREAM_PARSE, errorDescription);
                if (errorDescription) {
                    CFRelease(errorDescription);
                }
            }
        } else if (m_initializationError == kAudioConverterErr_FormatNotSupported) {
            CFStringRef sourceFormat = sourceFormatDescription();
            
            CFStringRef errorDescription = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@ not supported for streaming"), sourceFormat);
            
            closeAndSignalError(AS_ERR_UNSUPPORTED_FORMAT, errorDescription);
            if (errorDescription) {
                CFRelease(errorDescription);
            }
            if (sourceFormat) {
                CFRelease(sourceFormat);
            }
        } else if (m_initializationError != noErr) {
            CFStringRef errorDescription = coreAudioErrorToCFString(CFSTR("Error in audio stream initialization"), m_initializationError);
            closeAndSignalError(AS_ERR_OPEN, errorDescription);
            if (errorDescription) {
                CFRelease(errorDescription);
            }
        } else {
            m_discontinuity = false;
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

    if (!(contentLength() > 0)) {
        /* Continuous streams are not supposed to end */
        
        closeAndSignalError(AS_ERR_NETWORK, CFSTR("Stream ended abruptly"));
        
        return;
    }
    
    setState(END_OF_FILE);
    
    if (m_inputStream) {
        m_inputStream->close();
    }
    m_inputStreamRunning = false;
    
    if (m_audioQueueTimer) {
        CFRunLoopTimerInvalidate(m_audioQueueTimer);
        CFRelease(m_audioQueueTimer), m_audioQueueTimer = 0;
    }
    
    CFRunLoopTimerContext ctx = {0, this, NULL, NULL, NULL};
    
    m_audioQueueTimer = CFRunLoopTimerCreate(NULL,
                                           CFAbsoluteTimeGetCurrent(),
                                           0.050, // 50 ms
                                           0,
                                           0,
                                           audioQueueTimerCallback,
                                           &ctx);
    
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), m_audioQueueTimer, kCFRunLoopCommonModes);
}

void Audio_Stream::streamErrorOccurred(CFStringRef errorDesc)
{
    AS_TRACE("%s\n", __PRETTY_FUNCTION__);
    
    if (!m_inputStreamRunning) {
        AS_TRACE("%s: stray callback detected!\n", __PRETTY_FUNCTION__);
        return;
    }
    
    closeAndSignalError(AS_ERR_NETWORK, errorDesc);
}
    
void Audio_Stream::streamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData)
{
    if (m_delegate) {
        m_delegate->audioStreamMetaDataAvailable(metaData);
    }
}
    
void Audio_Stream::streamMetaDataByteSizeAvailable(UInt32 sizeInBytes)
{
    m_metaDataSizeInBytes = sizeInBytes;
    
    AS_TRACE("metadata size received %i\n", m_metaDataSizeInBytes);
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
    
    m_audioQueueConsumedPackets = false;
    
    m_audioQueue->m_delegate = 0;
    delete m_audioQueue, m_audioQueue = 0;
}
    
UInt64 Audio_Stream::defaultContentLength()
{
    return m_defaultContentLength;
}
    
UInt64 Audio_Stream::contentLength()
{
    if (m_contentLength == 0) {
        if (m_inputStream) {
            m_contentLength = m_inputStream->contentLength();
            if (m_contentLength == 0) {
                m_contentLength = defaultContentLength();
            }
        }
    }
    return m_contentLength;
}

void Audio_Stream::closeAndSignalError(int errorCode, CFStringRef errorDescription)
{
    AS_TRACE("%s: error %i\n", __PRETTY_FUNCTION__, errorCode);
    
    setState(FAILED);
    close(true);
    
    if (m_delegate) {
        m_delegate->audioStreamErrorOccurred(errorCode, errorDescription);
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
    
float Audio_Stream::bitrate()
{
    // Use the stream provided bit rate, if available
    if (m_bitRate > 0) {
        return m_bitRate;
    }
    
    // Stream didn't provide a bit rate, so let's calculate it
    if (m_bitrateBufferIndex < kAudioStreamBitrateBufferSize) {
        return 0;
    }
    double sum = 0;
    
    for (size_t i=0; i < kAudioStreamBitrateBufferSize; i++) {
        sum += m_bitrateBuffer[i];
    }
    
    return sum / (float)kAudioStreamBitrateBufferSize;
}
    
void Audio_Stream::watchdogTimerCallback(CFRunLoopTimerRef timer, void *info)
{
    Audio_Stream *THIS = (Audio_Stream *)info;
    
    if (PLAYING != THIS->state()) {
        Stream_Configuration *config = Stream_Configuration::configuration();
        
        CFStringRef errorDescription = CFStringCreateWithFormat(NULL, NULL, CFSTR("The stream startup watchdog activated: stream didn't start to play in %d seconds"), config->startupWatchdogPeriod);
        
        THIS->closeAndSignalError(AS_ERR_OPEN, errorDescription);
        if (errorDescription) {
            CFRelease(errorDescription);
        }
    }
}
    
void Audio_Stream::audioQueueTimerCallback(CFRunLoopTimerRef timer, void *info)
{
    AS_TRACE("audioQueueTimerCallback called\n");
    
    Audio_Stream *THIS = (Audio_Stream *)info;

    if (THIS->state() == SEEKING || THIS->state() == PAUSED) {
        return;
    }
    
    if (THIS->m_inputStreamRunning) {
        /* We are not needed, the input stream will drive the queue */
        return;
    }
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    int count = THIS->playbackDataCount();
    
    if (count > 0) {
        THIS->enqueueCachedData(config->decodeQueueSize);
    }
}
    
void Audio_Stream::createWatchdogTimer()
{
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    if (!(config->startupWatchdogPeriod > 0)) {
        return;
    }
    
    invalidateWatchdogTimer();
    
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
    
void Audio_Stream::invalidateWatchdogTimer()
{
    if (m_watchdogTimer) {
        CFRunLoopTimerInvalidate(m_watchdogTimer);
        CFRelease(m_watchdogTimer), m_watchdogTimer = 0;
        
        AS_TRACE("Watchdog invalidated\n");
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
    
int Audio_Stream::playbackDataCount()
{
    int count = 0;
    queued_packet_t *cur = m_playPacket;
    while (cur) {
        cur = cur->next;
        count++;
    }
    return count;
}
    
int Audio_Stream::audioQueueNumberOfBuffersInUse()
{
    int count = 0;
    if (m_audioQueue) {
        count = audioQueue()->numberOfBuffersInUse();
    }
    return count;
}
    
int Audio_Stream::audioQueuePacketCount()
{
    int count = 0;
    if (m_audioQueue) {
        count = audioQueue()->packetCount();
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
    
    if (state() == PAUSED || state() == SEEKING) {
        return;
    }
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    const bool continuous = (!(contentLength() > 0));
    const int count = playbackDataCount();
    
    if (!m_initialBufferingCompleted) {
        // Check if we have enough prebuffered data to start playback
        
        AS_TRACE("initial buffering not completed, checking if enough data\n");
        
        int lim;
        
        if (continuous) {
            // Continuous stream
            lim = config->requiredInitialPrebufferedByteCountForContinuousStream;
            AS_TRACE("continuous stream, %i bytes must be cached to start the playback\n", lim);
        } else {
            // Non-continuous
            lim = config->requiredInitialPrebufferedByteCountForNonContinuousStream;
            AS_TRACE("non-continuous stream, %i bytes must be cached to start the playback\n", lim);
        }
        
        if (m_cachedDataSize > lim) {
            AS_TRACE("buffered %zu bytes, required for playback %i, starting playback\n", m_cachedDataSize, lim);
            
            m_initialBufferingCompleted = true;
        } else {
            AS_TRACE("not enough cached data to start playback\n");
        }
    }
    
    // If the stream has never started playing and we have received 90% of the data of the stream,
    // let's override the limits
    if (!m_audioQueueConsumedPackets && contentLength() > 0) {
        const UInt64 seekLength = contentLength() * m_seekOffset;
        
        AS_TRACE("seek length %llu\n", seekLength);
        
        const UInt64 numBytesRequiredToBeBuffered = (contentLength() - seekLength) * 0.9;
        
        AS_TRACE("audio queue not consumed packets, content length %llu, required bytes to be buffered %llu\n", contentLength(), numBytesRequiredToBeBuffered);
        
        if (m_bytesReceived >= numBytesRequiredToBeBuffered) {
            m_initialBufferingCompleted = true;
            m_ignoreDecodeQueueSize = true;
            
            AS_TRACE("%llu bytes received, overriding buffering limits\n", m_bytesReceived);
        }
    }
    
    if (!m_preloading && m_initialBufferingCompleted && (count > minPacketsRequired || m_ignoreDecodeQueueSize)) {
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
        
        OSStatus err = AudioConverterFillComplexBuffer(m_audioConverter,
                                                       &encoderDataCallback,
                                                       this,
                                                       &ioOutputDataPackets,
                                                       &outputBufferList,
                                                       NULL);
        if (err == noErr) {
            AS_TRACE("%i output bytes available for the audio queue\n", (unsigned int)ioOutputDataPackets);
            
            invalidateWatchdogTimer();
            
            setState(PLAYING);
            
            m_audioQueueConsumedPackets = true;
            
            audioQueue()->handleAudioPackets(outputBufferList.mBuffers[0].mDataByteSize,
                                                   outputBufferList.mNumberBuffers,
                                                   outputBufferList.mBuffers[0].mData,
                                                   &description);
            
            if (m_delegate) {
                m_delegate->samplesAvailable(outputBufferList, description);
            }
            
            // For continuous streams, we don't need to accummulate the data for seeking
            if (continuous) {
                cleanupCachedData();
            } else {
                // For non-continuous streams, keep previous data for seeking
                if (m_cachedDataSize >= config->maxPrebufferedByteCount) {
                    cleanupCachedData();
                }
            }
        } else {
            AS_TRACE("AudioConverterFillComplexBuffer failed, error %i\n", err);
        }
    } else {
        AS_TRACE("Less than %i packets queued, returning...\n", minPacketsRequired);
    }
}
    
void Audio_Stream::cleanupCachedData()
{
    if (m_processedPackets.size() == 0) {
        // Nothing can be cleaned yet, sorry
        AS_TRACE("Cache cleanup called but no free packets\n");
        return;
    }
    
    queued_packet_t *lastPacket = m_processedPackets.back();
    
    bool keepCleaning = true;
    queued_packet_t *cur = m_queuedHead;
    while (cur && keepCleaning) {
        if (cur->identifier == lastPacket->identifier) {
            AS_TRACE("Found the last packet to be cleaned up\n");
            keepCleaning  = false;
        }
        
        queued_packet_t *tmp = cur->next;
        
        m_cachedDataSize -= cur->desc.mDataByteSize;
        
        free(cur);
        cur = tmp;
        if (cur == m_playPacket){
            keepCleaning = false;
            AS_TRACE("Found m_playPacket\n");
        }
    }
    m_queuedHead = cur;
    
    m_processedPackets.clear();
    
    if (m_inputStream) {
        AS_TRACE("Cache underflow, enabling the HTTP stream\n");
        m_inputStream->setScheduledInRunLoop(true);
    }
}
    
OSStatus Audio_Stream::encoderDataCallback(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    Audio_Stream *THIS = (Audio_Stream *)inUserData;
    
    AS_TRACE("encoderDataCallback called\n");
    
    // Dequeue one packet per time for the decoder
    queued_packet_t *front = THIS->m_playPacket;
    
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
    
    THIS->m_playPacket = front->next;
    
    THIS->m_processedPackets.push_front(front);
    
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
        case kAudioFileStreamProperty_BitRate: {
            bool sizeReceivedForFirstTime = (THIS->m_bitRate == 0);
            UInt32 bitRateSize = sizeof(THIS->m_bitRate);
            OSStatus err = AudioFileStreamGetProperty(inAudioFileStream,
                                                      kAudioFileStreamProperty_BitRate,
                                                      &bitRateSize, &THIS->m_bitRate);
            if (err) {
                THIS->m_bitRate = 0;
            } else {
                if (THIS->m_delegate && sizeReceivedForFirstTime) {
                    THIS->m_delegate->bitrateAvailable();
                }
            }
            break;
        }
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
            UInt32 byteCountSize = sizeof(THIS->m_audioDataByteCount);
            OSStatus err = AudioFileStreamGetProperty(inAudioFileStream,
                                                      kAudioFileStreamProperty_AudioDataByteCount,
                                                      &byteCountSize, &THIS->m_audioDataByteCount);
            if (err) {
                THIS->m_audioDataByteCount = 0;
            }
            break;
        }
        case kAudioFileStreamProperty_AudioDataPacketCount: {
            UInt32 packetCountSize = sizeof(THIS->m_audioDataPacketCount);
            OSStatus err = AudioFileStreamGetProperty(inAudioFileStream,
                                                      kAudioFileStreamProperty_AudioDataPacketCount,
                                                      &packetCountSize, &THIS->m_audioDataPacketCount);
            if (err) {
                THIS->m_audioDataPacketCount = 0;
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
            
            THIS->audioQueue()->init();
            break;
        }
        default: {
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
        
        packet->identifier = THIS->m_packetIdentifier;
        
        // If the stream didn't provide bitRate (m_bitRate == 0), then let's calculate it
        if (THIS->m_bitRate == 0 && THIS->m_bitrateBufferIndex < kAudioStreamBitrateBufferSize) {
            // Only keep sampling for one buffer cycle; this is to keep the counters (for instance) duration
            // stable.
            
            THIS->m_bitrateBuffer[THIS->m_bitrateBufferIndex++] = 8 * inPacketDescriptions[i].mDataByteSize / THIS->m_packetDuration;
            
            if (THIS->m_bitrateBufferIndex == kAudioStreamBitrateBufferSize) {
                if (THIS->m_delegate) {
                    THIS->m_delegate->bitrateAvailable();
                }
            }
        }
        
        /* Prepare the packet */
        packet->next = NULL;
        packet->desc = inPacketDescriptions[i];
        packet->desc.mStartOffset = 0;
        memcpy(packet->data, (const char *)inInputData + inPacketDescriptions[i].mStartOffset,
               size);
        
        if (THIS->m_queuedHead == NULL) {
            THIS->m_queuedHead = THIS->m_queuedTail = THIS->m_playPacket = packet;
        } else {
            THIS->m_queuedTail->next = packet;
            THIS->m_queuedTail = packet;
        }
        
        THIS->m_cachedDataSize += size;
        
        THIS->m_packetIdentifier++;
        
        if (THIS->m_cachedDataSize >= config->maxPrebufferedByteCount) {
            AS_TRACE("Cache overflow, disabling the HTTP stream\n");
            
            if (THIS->m_inputStream) {
                THIS->m_inputStream->setScheduledInRunLoop(false);
            }
            
            THIS->cleanupCachedData();
        }
    }
    
    THIS->enqueueCachedData(config->decodeQueueSize);
}

} // namespace astreamer