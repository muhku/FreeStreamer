/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 *
 * Part of the code in this file has been rewritten from
 * the AudioFileStreamExample / afsclient.cpp
 * example, Copyright © 2007 Apple Inc.
 *
 * The threadless playback has been adapted from
 * Alex Crichton's AudioStreamer.
 */

#include "audio_queue.h"

#include <cassert>

//#define AQ_DEBUG 1

#if !defined (AQ_DEBUG)
    #define AQ_TRACE(...) do {} while (0)
#else
    #define AQ_TRACE(...) printf(__VA_ARGS__)
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
    m_processedPacketsSizeTotal(0),
    m_processedPacketsCount(0),
    m_audioQueueStarted(false),
    m_waitingOnBuffer(false),
    m_queuedHead(0),
    m_queuedTail(0),
    m_lastError(noErr)
{
    for (size_t i=0; i < AQ_BUFFERS; i++) {
        m_bufferInUse[i] = false;
    }
}
    
Audio_Queue::~Audio_Queue()
{
    stop(true);
    
    cleanup();
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
    
double Audio_Queue::packetDuration()
{
    return m_streamDesc.mFramesPerPacket / m_streamDesc.mSampleRate;
}
    
unsigned Audio_Queue::timePlayedInSeconds()
{
    unsigned timePlayed = 0;
    
    AudioTimeStamp queueTime;
    Boolean discontinuity;
    
    OSStatus err = AudioQueueGetCurrentTime(m_outAQ, NULL, &queueTime, &discontinuity);
    if (err) {
        goto out;
    }
    
    timePlayed = queueTime.mSampleTime / m_streamDesc.mSampleRate;
    
out:
    return timePlayed;
}
    
unsigned Audio_Queue::bitrate()
{
    unsigned bitrate = 0;
    
    double packetDuration = this->packetDuration();
    
    if (packetDuration > 0 && m_processedPacketsCount > 50) {
        double averagePacketByteSize = m_processedPacketsSizeTotal / m_processedPacketsCount;
        bitrate = 8 * averagePacketByteSize / packetDuration;
    }
    
    return bitrate;
}

void Audio_Queue::handlePropertyChange(AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
{
    OSStatus err = noErr;
    
    AQ_TRACE("found property '%lu%lu%lu%lu'\n", (inPropertyID>>24)&255, (inPropertyID>>16)&255, (inPropertyID>>8)&255, inPropertyID&255);
    
    switch (inPropertyID) {
        case kAudioFileStreamProperty_ReadyToProducePackets:
        {
            cleanup();
            
            // the file stream parser is now ready to produce audio packets.
            // get the stream format.
            memset(&m_streamDesc, 0, sizeof(m_streamDesc));
            UInt32 asbdSize = sizeof(m_streamDesc);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &m_streamDesc);
            if (err) {
                AQ_TRACE("%s: error in kAudioFileStreamProperty_DataFormat\n", __PRETTY_FUNCTION__);
                m_lastError = err;
                break;
            }
            
            // create the audio queue
            err = AudioQueueNewOutput(&m_streamDesc, audioQueueOutputCallback, this, CFRunLoopGetCurrent(), NULL, 0, &m_outAQ);
            if (err) {
                AQ_TRACE("%s: error in AudioQueueNewOutput\n", __PRETTY_FUNCTION__);
                
                if (m_delegate) {
                    m_delegate->audioQueueInitializationFailed();
                }
                
                m_lastError = err;
                break;
            }
            
            // allocate audio queue buffers
            for (unsigned int i = 0; i < AQ_BUFFERS; ++i) {
                err = AudioQueueAllocateBuffer(m_outAQ, AQ_BUFSIZ, &m_audioQueueBuffer[i]);
                if (err) {
                    /* If allocating the buffers failed, everything else will fail, too.
                     *  Dispose the queue so that we can later on detect that this
                     *  queue in fact has not been initialized.
                     */
                    
                    AQ_TRACE("%s: error in AudioQueueAllocateBuffer\n", __PRETTY_FUNCTION__);
                    
                    (void)AudioQueueDispose(m_outAQ, true);
                    m_outAQ = 0;
                    
                    if (m_delegate) {
                        m_delegate->audioQueueInitializationFailed();
                    }
                    
                    m_lastError = err;
                    break;
                }
            }
            
            setCookiesForStream(inAudioFileStream);
            
            // listen for kAudioQueueProperty_IsRunning
            err = AudioQueueAddPropertyListener(m_outAQ, kAudioQueueProperty_IsRunning, audioQueueIsRunningCallback, this);
            if (err) {
                AQ_TRACE("%s: error in AudioQueueAddPropertyListener\n", __PRETTY_FUNCTION__);
                m_lastError = err;
                break;
            }
            
            break;
        }
    }
}

void Audio_Queue::handleAudioPackets(UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions)
{
    if (!initialized()) {
        AQ_TRACE("%s: warning: attempt to handle audio packets with uninitialized audio queue. return.\n", __PRETTY_FUNCTION__);
        
        return;
    }
    
    // this is called by audio file stream when it finds packets of audio
    AQ_TRACE("got data.  bytes: %lu  packets: %lu\n", inNumberBytes, inNumberPackets);
    
    /* Place each packet into a buffer and then send each buffer into the audio
     queue */
    UInt32 i;
    
    if (!inPacketDescriptions) {
        AQ_TRACE("%s: notice: supplying the packet descriptions for a supposed CBR data.\n", __PRETTY_FUNCTION__);
        
        // If no packet descriptions are supplied, assume we are dealing with CBR data
        UInt32 base = inNumberBytes / inNumberPackets;
        AudioStreamPacketDescription *descriptions = new AudioStreamPacketDescription[inNumberPackets];
        
        for (i = 0; i < inNumberPackets; i++) {
            descriptions[i].mStartOffset = (base * i);
            descriptions[i].mDataByteSize = base;
            descriptions[i].mVariableFramesInPacket = 0;
        }
        inPacketDescriptions = descriptions;
        
        m_cbrPacketDescriptions.push_back(descriptions);
    }
    
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
    
    AQ_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    UInt32 packetSize = desc->mDataByteSize;
    
    /* This shouldn't happen because most of the time we read the packet buffer
     size from the file stream, but if we restored to guessing it we could
     come up too small here */
    if (packetSize > AQ_BUFSIZ) {
        AQ_TRACE("%s: packetSize %lli > AQ_BUFSIZ %li\n", __PRETTY_FUNCTION__, packetSize, AQ_BUFSIZ);
        return -1;
    }
    
    // if the space remaining in the buffer is not enough for this packet, then
    // enqueue the buffer and wait for another to become available.
    if (AQ_BUFSIZ - m_bytesFilled < packetSize) {
        int hasFreeBuffer = enqueueBuffer();
        if (hasFreeBuffer <= 0) {
            return hasFreeBuffer;
        }
    } else {
        AQ_TRACE("%s: skipped enqueueBuffer AQ_BUFSIZ - m_bytesFilled %lu, packetSize %lli\n", __PRETTY_FUNCTION__, (AQ_BUFSIZ - m_bytesFilled), packetSize);
    }
    
    m_processedPacketsSizeTotal += packetSize;
    m_processedPacketsCount++;
    
    // copy data to the audio queue buffer
    AudioQueueBufferRef buf = m_audioQueueBuffer[m_fillBufferIndex];
    memcpy((char*)buf->mAudioData + m_bytesFilled, data, packetSize);
    
    // fill out packet description to pass to enqueue() later on
    m_packetDescs[m_packetsFilled] = *desc;
    // Make sure the offset is relative to the start of the audio buffer
    m_packetDescs[m_packetsFilled].mStartOffset = m_bytesFilled;
    // keep track of bytes filled and packets filled
    m_bytesFilled += packetSize;
    m_packetsFilled++;
    
    /* Maximum number of packets which can be contained in one buffer */
#define kAQMaxPacketDescs 512
    
    /* If filled our buffer with packets, then commit it to the system */
    if (m_packetsFilled >= kAQMaxPacketDescs) {
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
    
    if (AudioQueueDispose(m_outAQ, true) != 0) {
        AQ_TRACE("%s: AudioQueueDispose failed!\n", __PRETTY_FUNCTION__);
    }
    m_outAQ = 0;
    m_fillBufferIndex = m_bytesFilled = m_packetsFilled = m_buffersUsed = m_processedPacketsSizeTotal = m_processedPacketsCount = 0;
    
    for (size_t i=0; i < AQ_BUFFERS; i++) {
        m_bufferInUse[i] = false;
    }
    
    queued_packet_t *cur = m_queuedHead;
    while (cur) {
        queued_packet_t *tmp = cur->next;
        free(cur);
        cur = tmp;
    }
    m_queuedHead = m_queuedHead = 0;
    
    for (size_t i=0; i < m_cbrPacketDescriptions.size(); i++) {
        delete[] m_cbrPacketDescriptions[i];
    }
    m_cbrPacketDescriptions.clear();
    
    m_waitingOnBuffer = false;
    m_lastError = noErr;
}
    
void Audio_Queue::setCookiesForStream(AudioFileStreamID inAudioFileStream)
{
    OSStatus err;
    
    // get the cookie size
    UInt32 cookieSize;
    Boolean writable;
    
    err = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (err) {
        AQ_TRACE("error in info kAudioFileStreamProperty_MagicCookieData\n");
        return;
    }
    AQ_TRACE("cookieSize %lu\n", cookieSize);
    
    // get the cookie data
    void* cookieData = calloc(1, cookieSize);
    err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (err) {
        AQ_TRACE("error in get kAudioFileStreamProperty_MagicCookieData");
        free(cookieData);
        return;
    }
    
    // set the cookie on the queue.
    err = AudioQueueSetProperty(m_outAQ, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
    free(cookieData);
    if (err) {
        AQ_TRACE("error in set kAudioQueueProperty_MagicCookie");
    }
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
    assert(!m_bufferInUse[m_fillBufferIndex]);
    
    AQ_TRACE("%s: enter\n", __PRETTY_FUNCTION__);
    
    m_bufferInUse[m_fillBufferIndex] = true;
    m_buffersUsed++;
    
    // enqueue buffer
    AudioQueueBufferRef fillBuf = m_audioQueueBuffer[m_fillBufferIndex];
    fillBuf->mAudioDataByteSize = m_bytesFilled;
    
    assert(m_packetsFilled > 0);
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
    if (++m_fillBufferIndex >= AQ_BUFFERS) {
        m_fillBufferIndex = 0; 
    }
    // reset bytes filled
    m_bytesFilled = 0;
    // reset packets filled
    m_packetsFilled = 0;
    
    // wait until next buffer is not in use
    if (m_bufferInUse[m_fillBufferIndex]) {
        AQ_TRACE("waiting for buffer %lu\n", m_fillBufferIndex);
        
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
    for (unsigned int i = 0; i < AQ_BUFFERS; ++i) {
        if (inBuffer == m_audioQueueBuffer[i]) {
            AQ_TRACE("findQueueBuffer %i\n", i);
            return i;
        }
    }
    return -1;
}
    
void Audio_Queue::enqueueCachedData()
{
    assert(!m_waitingOnBuffer);
    assert(!m_bufferInUse[m_fillBufferIndex]);
    
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
    
    assert(audioQueue->m_bufferInUse[bufIndex]);
    
    audioQueue->m_bufferInUse[bufIndex] = false;
    audioQueue->m_buffersUsed--;
    
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