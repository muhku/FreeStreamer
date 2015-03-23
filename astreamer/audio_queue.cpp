/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2015 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 *
 * Part of the code in this file has been rewritten from
 * the AudioFileStreamExample / afsclient.cpp
 * example, Copyright © 2007 Apple Inc.
 *
 * The threadless playback has been adapted from
 * Alex Crichton's AudioStreamer.
 */

#include "audio_queue.h"
#include "stream_configuration.h"

//#define AQ_DEBUG 1

#if !defined (AQ_DEBUG)
    #define AQ_TRACE(...) do {} while (0)
    #define AQ_ASSERT(...) do {} while (0)
#else
    #include <cassert>

    #define AQ_TRACE(...) printf(__VA_ARGS__)
    #define AQ_ASSERT(...) assert(__VA_ARGS__)
#endif

namespace astreamer {
    
typedef struct queued_packet {
    AudioStreamPacketDescription desc;
    struct queued_packet *next;
    char data[];
} queued_packet_t;
    
/* public */    
    
Audio_Queue::Audio_Queue()
    : m_delegate(0),
    m_state(IDLE),
    m_outAQ(0),
    m_fillBufferIndex(0),
    m_bytesFilled(0),
    m_packetsFilled(0),
    m_buffersUsed(0),
    m_audioQueueStarted(false),
    m_waitingOnBuffer(false),
    m_queuedHead(0),
    m_queuedTail(0),
    m_lastError(noErr),
    m_initialOutputVolume(1.0)
{
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    m_audioQueueBuffer = new AudioQueueBufferRef[config->bufferCount];
    m_packetDescs = new AudioStreamPacketDescription[config->maxPacketDescs];
    m_bufferInUse = new bool[config->bufferCount];
    
    for (size_t i=0; i < config->bufferCount; i++) {
        m_bufferInUse[i] = false;
    }
}
    
Audio_Queue::~Audio_Queue()
{
    stop(true);
    
    cleanup();
    
    delete [] m_audioQueueBuffer;
    delete [] m_packetDescs;
    delete [] m_bufferInUse;
}
    
bool Audio_Queue::initialized()
{
    return (m_outAQ != 0);
}
    
void Audio_Queue::start()
{
    // start the queue if it has not been started already
    if (m_audioQueueStarted) {
        return;
    }
            
    OSStatus err = AudioQueueStart(m_outAQ, NULL);
    if (!err) {
        m_audioQueueStarted = true;
        m_lastError = noErr;
    } else {
        AQ_TRACE("%s: AudioQueueStart failed!\n", __PRETTY_FUNCTION__);
        m_lastError = err;
    }
}
    
void Audio_Queue::pause()
{
    if (m_state == RUNNING) {
        if (AudioQueuePause(m_outAQ) != 0) {
            AQ_TRACE("%s: AudioQueuePause failed!\n", __PRETTY_FUNCTION__);
        }
        setState(PAUSED);
    } else if (m_state == PAUSED) {
        AudioQueueStart(m_outAQ, NULL);
        setState(RUNNING);
    }
}
    
void Audio_Queue::stop()
{
    stop(true);
}
    
float Audio_Queue::volume()
{
    if (!m_outAQ) {
        return 1.0;
    }
    
    float vol;
    
    OSStatus err = AudioQueueGetParameter(m_outAQ, kAudioQueueParam_Volume, &vol);
    
    if (!err) {
        return vol;
    }
    
    return 1.0;
}
    
void Audio_Queue::setVolume(float volume)
{
    if (!m_outAQ) {
        return;
    }
    AudioQueueSetParameter(m_outAQ, kAudioQueueParam_Volume, volume);
}
    
void Audio_Queue::setPlayRate(float playRate)
{
    if (!m_outAQ) {
        return;
    }
    UInt32 enableTimePitchConversion = (playRate != 1.0);
    
    if (playRate < 0.5) {
        playRate = 0.5;
    }
    if (playRate > 2.0) {
        playRate = 2.0;
    }

    AudioQueueSetProperty (m_outAQ, kAudioQueueProperty_EnableTimePitch, &enableTimePitchConversion, sizeof(enableTimePitchConversion));
    
    AudioQueueSetParameter(m_outAQ, kAudioQueueParam_PlayRate, playRate);
}

void Audio_Queue::stop(bool stopImmediately)
{
    if (!m_audioQueueStarted) {
        AQ_TRACE("%s: audio queue already stopped, return!\n", __PRETTY_FUNCTION__);
        return;
    }
    m_audioQueueStarted = false;
    
    AQ_TRACE("%s: enter\n", __PRETTY_FUNCTION__);

    if (AudioQueueFlush(m_outAQ) != 0) {
        AQ_TRACE("%s: AudioQueueFlush failed!\n", __PRETTY_FUNCTION__);
    }
    
    if (stopImmediately) {
        AudioQueueRemovePropertyListener(m_outAQ,
                                         kAudioQueueProperty_IsRunning,
                                         audioQueueIsRunningCallback,
                                         this);
    }
    
    if (AudioQueueStop(m_outAQ, stopImmediately) != 0) {
        AQ_TRACE("%s: AudioQueueStop failed!\n", __PRETTY_FUNCTION__);
    }
    
    if (stopImmediately) {
        setState(IDLE);
    }
    
    AQ_TRACE("%s: leave\n", __PRETTY_FUNCTION__);
}
    
AudioTimeStamp Audio_Queue::currentTime()
{
    AudioTimeStamp queueTime;
    Boolean discontinuity;
    
    memset(&queueTime, 0, sizeof queueTime);
    
    OSStatus err = AudioQueueGetCurrentTime(m_outAQ, NULL, &queueTime, &discontinuity);
    if (err) {
        AQ_TRACE("AudioQueueGetCurrentTime failed\n");
    }
    
    return queueTime;
}
    
int Audio_Queue::numberOfBuffersInUse()
{
    Stream_Configuration *config = Stream_Configuration::configuration();
    int count = 0;
    for (size_t i=0; i < config->bufferCount; i++) {
        if (m_bufferInUse[i]) {
            count++;
        }
    }
    return count;
}
    
int Audio_Queue::packetCount()
{
    int count = 0;
    queued_packet_t *cur = m_queuedHead;
    while (cur) {
        cur = cur->next;
        count++;
    }
    return count;
}

void Audio_Queue::init()
{
    OSStatus err = noErr;
    
    cleanup();
        
    // create the audio queue
    err = AudioQueueNewOutput(&m_streamDesc, audioQueueOutputCallback, this, CFRunLoopGetCurrent(), NULL, 0, &m_outAQ);
    if (err) {
        AQ_TRACE("%s: error in AudioQueueNewOutput\n", __PRETTY_FUNCTION__);
        
        m_lastError = err;
        
        if (m_delegate) {
            m_delegate->audioQueueInitializationFailed();
        }
        
        return;
    }
    
    Stream_Configuration *configuration = Stream_Configuration::configuration();
    
    // allocate audio queue buffers
    for (unsigned int i = 0; i < configuration->bufferCount; ++i) {
        err = AudioQueueAllocateBuffer(m_outAQ, configuration->bufferSize, &m_audioQueueBuffer[i]);
        if (err) {
            /* If allocating the buffers failed, everything else will fail, too.
             *  Dispose the queue so that we can later on detect that this
             *  queue in fact has not been initialized.
             */
            
            AQ_TRACE("%s: error in AudioQueueAllocateBuffer\n", __PRETTY_FUNCTION__);
            
            (void)AudioQueueDispose(m_outAQ, true);
            m_outAQ = 0;
            
            m_lastError = err;
            
            if (m_delegate) {
                m_delegate->audioQueueInitializationFailed();
            }
            
            return;
        }
    }
    
    // listen for kAudioQueueProperty_IsRunning
    err = AudioQueueAddPropertyListener(m_outAQ, kAudioQueueProperty_IsRunning, audioQueueIsRunningCallback, this);
    if (err) {
        AQ_TRACE("%s: error in AudioQueueAddPropertyListener\n", __PRETTY_FUNCTION__);
        m_lastError = err;
        return;
    }
    
    if (m_initialOutputVolume != 1.0) {
        setVolume(m_initialOutputVolume);
    }
}

void Audio_Queue::handleAudioPackets(UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions)
{
    if (!initialized()) {
        AQ_TRACE("%s: warning: attempt to handle audio packets with uninitialized audio queue. return.\n", __PRETTY_FUNCTION__);
        
        return;
    }
    
    // this is called by audio file stream when it finds packets of audio
    AQ_TRACE("got data.  bytes: %u  packets: %u\n", inNumberBytes, (unsigned int)inNumberPackets);
    
    /* Place each packet into a buffer and then send each buffer into the audio
     queue */
    UInt32 i;
    
    for (i = 0; i < inNumberPackets && !m_waitingOnBuffer && m_queuedHead == NULL; i++) {
        AudioStreamPacketDescription *desc = &inPacketDescriptions[i];
        int ret = handlePacket((const char*)inInputData + desc->mStartOffset, desc);
        if (!ret) break;
    }
    if (i == inNumberPackets) {
        return;
    }
    
    for (; i < inNumberPackets; i++) {
        /* Allocate the packet */
        UInt32 size = inPacketDescriptions[i].mDataByteSize;
        queued_packet_t *packet = (queued_packet_t *)malloc(sizeof(queued_packet_t) + size);
        
        /* Prepare the packet */
        packet->next = NULL;
        packet->desc = inPacketDescriptions[i];
        packet->desc.mStartOffset = 0;
        memcpy(packet->data, (const char *)inInputData + inPacketDescriptions[i].mStartOffset,
               size);
        
        if (m_queuedHead == NULL) {
            m_queuedHead = m_queuedTail = packet;
        } else {
            m_queuedTail->next = packet;
            m_queuedTail = packet;
        }
    }
}
    
int Audio_Queue::handlePacket(const void *data, AudioStreamPacketDescription *desc)
{
    if (!initialized()) {
        AQ_TRACE("%s: warning: attempt to handle audio packets with uninitialized audio queue. return.\n", __PRETTY_FUNCTION__);
        
        return -1;
    }
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    AQ_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    UInt32 packetSize = desc->mDataByteSize;
    
    /* This shouldn't happen because most of the time we read the packet buffer
     size from the file stream, but if we restored to guessing it we could
     come up too small here */
    if (packetSize > config->bufferSize) {
        AQ_TRACE("%s: packetSize %u > AQ_BUFSIZ %li\n", __PRETTY_FUNCTION__, (unsigned int)packetSize, config->bufferSize);
        return -1;
    }
    
    // if the space remaining in the buffer is not enough for this packet, then
    // enqueue the buffer and wait for another to become available.
    if (config->bufferSize - m_bytesFilled < packetSize) {
        int hasFreeBuffer = enqueueBuffer();
        if (hasFreeBuffer <= 0) {
            return hasFreeBuffer;
        }
    } else {
        AQ_TRACE("%s: skipped enqueueBuffer AQ_BUFSIZ - m_bytesFilled %lu, packetSize %u\n", __PRETTY_FUNCTION__, (config->bufferSize - m_bytesFilled), (unsigned int)packetSize);
    }
    
    // copy data to the audio queue buffer
    AudioQueueBufferRef buf = m_audioQueueBuffer[m_fillBufferIndex];
    memcpy((char*)buf->mAudioData, data, packetSize);
    
    // fill out packet description to pass to enqueue() later on
    m_packetDescs[m_packetsFilled] = *desc;
    // Make sure the offset is relative to the start of the audio buffer
    m_packetDescs[m_packetsFilled].mStartOffset = m_bytesFilled;
    // keep track of bytes filled and packets filled
    m_bytesFilled += packetSize;
    m_packetsFilled++;
    
    /* If filled our buffer with packets, then commit it to the system */
    if (m_packetsFilled >= config->maxPacketDescs) {
        return enqueueBuffer();
    }
    return 1;
}

/* private */
    
void Audio_Queue::cleanup()
{
    if (!initialized()) {
        AQ_TRACE("%s: warning: attempt to cleanup an uninitialized audio queue. return.\n", __PRETTY_FUNCTION__);
        
        return;
    }
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    if (m_state != IDLE) {
        AQ_TRACE("%s: attemping to cleanup the audio queue when it is still playing, force stopping\n",
                 __PRETTY_FUNCTION__);
        
        AudioQueueRemovePropertyListener(m_outAQ,
                                         kAudioQueueProperty_IsRunning,
                                         audioQueueIsRunningCallback,
                                         this);
        
        AudioQueueStop(m_outAQ, true);
        setState(IDLE);
    }
    
    if (AudioQueueDispose(m_outAQ, true) != 0) {
        AQ_TRACE("%s: AudioQueueDispose failed!\n", __PRETTY_FUNCTION__);
    }
    m_outAQ = 0;
    m_fillBufferIndex = m_bytesFilled = m_packetsFilled = m_buffersUsed = 0;
    
    for (size_t i=0; i < config->bufferCount; i++) {
        m_bufferInUse[i] = false;
    }
    
    queued_packet_t *cur = m_queuedHead;
    while (cur) {
        queued_packet_t *tmp = cur->next;
        free(cur);
        cur = tmp;
    }
    m_queuedHead = m_queuedTail = 0;
    
    m_waitingOnBuffer = false;
    m_lastError = noErr;
}
    
void Audio_Queue::setState(State state)
{
    if (m_state == state) {
        /* We are already in this state! */
        return;
    }
    
    m_state = state;
    
    if (m_delegate) {
        m_delegate->audioQueueStateChanged(m_state);
    }
}

int Audio_Queue::enqueueBuffer()
{
    AQ_ASSERT(!m_bufferInUse[m_fillBufferIndex]);
    
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    AQ_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    m_bufferInUse[m_fillBufferIndex] = true;
    m_buffersUsed++;
    
    // enqueue buffer
    AudioQueueBufferRef fillBuf = m_audioQueueBuffer[m_fillBufferIndex];
    fillBuf->mAudioDataByteSize = m_bytesFilled;
    
    AQ_ASSERT(m_packetsFilled > 0);
    OSStatus err = AudioQueueEnqueueBuffer(m_outAQ, fillBuf, m_packetsFilled, m_packetDescs);
    if (!err) {
        m_lastError = noErr;
        start();
    } else {
        /* If we get an error here, it very likely means that the audio queue is no longer
           running */
        AQ_TRACE("%s: error in AudioQueueEnqueueBuffer\n", __PRETTY_FUNCTION__);
        m_lastError = err;
        return 1;
    }
    
    // go to next buffer
    if (++m_fillBufferIndex >= config->bufferCount) {
        m_fillBufferIndex = 0; 
    }
    // reset bytes filled
    m_bytesFilled = 0;
    // reset packets filled
    m_packetsFilled = 0;
    
    // wait until next buffer is not in use
    if (m_bufferInUse[m_fillBufferIndex]) {
        AQ_TRACE("waiting for buffer %u\n", (unsigned int)m_fillBufferIndex);
        
        if (m_delegate) {
            m_delegate->audioQueueOverflow();
        }
        m_waitingOnBuffer = true;
        return 0;
    }
    
    return 1;
}
    
int Audio_Queue::findQueueBuffer(AudioQueueBufferRef inBuffer)
{
    Stream_Configuration *config = Stream_Configuration::configuration();
    
    for (unsigned int i = 0; i < config->bufferCount; ++i) {
        if (inBuffer == m_audioQueueBuffer[i]) {
            AQ_TRACE("findQueueBuffer %i\n", i);
            return i;
        }
    }
    return -1;
}
    
void Audio_Queue::enqueueCachedData()
{
    AQ_ASSERT(!m_waitingOnBuffer);
    AQ_ASSERT(!m_bufferInUse[m_fillBufferIndex]);
    
    /* Queue up as many packets as possible into the buffers */
    queued_packet_t *cur = m_queuedHead;
    while (cur) {
        int ret = handlePacket(cur->data, &cur->desc);
        if (ret == 0) {
           break; 
        }
        queued_packet_t *next = cur->next;
        free(cur);
        cur = next;
    }
    m_queuedHead = cur;
    
    /* If we finished queueing all our saved packets, we can re-schedule the
     * stream to run */
    if (cur == NULL) {
        m_queuedTail = NULL;
        if (m_delegate) {
            m_delegate->audioQueueUnderflow();
        }
    }
}
    
// this is called by the audio queue when it has finished decoding our data. 
// The buffer is now free to be reused.
void Audio_Queue::audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    Audio_Queue *audioQueue = static_cast<Audio_Queue*>(inClientData);    
    unsigned int bufIndex = audioQueue->findQueueBuffer(inBuffer);
    
    AQ_ASSERT(audioQueue->m_bufferInUse[bufIndex]);
    
    audioQueue->m_bufferInUse[bufIndex] = false;
    audioQueue->m_buffersUsed--;
    
    if (audioQueue->m_delegate) {
        audioQueue->m_delegate->audioQueueFinishedPlayingPacket();
    }
    
    if (audioQueue->m_buffersUsed == 0 && !audioQueue->m_queuedHead && audioQueue->m_delegate) {
        audioQueue->m_delegate->audioQueueBuffersEmpty();
    } else if (audioQueue->m_waitingOnBuffer) {
        audioQueue->m_waitingOnBuffer = false;
        audioQueue->enqueueCachedData();
    }
}

void Audio_Queue::audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    Audio_Queue *audioQueue = static_cast<Audio_Queue*>(inClientData);
    
    AQ_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    UInt32 running;
    UInt32 output = sizeof(running);
    OSStatus err = AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &running, &output);
    if (err) {
        AQ_TRACE("%s: error in kAudioQueueProperty_IsRunning\n", __PRETTY_FUNCTION__);
        return;
    }
    if (running) {
        AQ_TRACE("audio queue running!\n");
        audioQueue->setState(RUNNING);
    } else {
        audioQueue->setState(IDLE);
    }
}    
    
} // namespace astreamer
