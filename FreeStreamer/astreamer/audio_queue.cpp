/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * Part of the code in this file has been rewritten from
 * the AudioFileStreamExample / afsclient.cpp
 * example, Copyright © 2007 Apple Inc.
 */

#include "audio_queue.h"

#include <pthread.h>

//#define AQ_DEBUG 1

#if !defined (AQ_DEBUG)
    #define AQ_TRACE(...) do {} while (0)
#else
    #define AQ_TRACE(...) printf(__VA_ARGS__)
#endif

namespace astreamer {
    
/* public */    
    
Audio_Queue::Audio_Queue()
    : m_delegate(0),
    m_state(IDLE),
    m_outAQ(0),
    m_fillBufferIndex(0),
    m_bytesFilled(0),
    m_packetsFilled(0),
    m_audioQueueStarted(false),
    m_bufferInUseMutex(new pthread_mutex_t),
    m_bufferFreeCondition(new pthread_cond_t),
    m_lastError(noErr)
{
    for (size_t i=0; i < AQ_BUFFERS; i++) {
        m_bufferInUse[i] = false;
    }
    
    // initialize a mutex and condition so that we can block on buffers in use.
    if (pthread_mutex_init(m_bufferInUseMutex, NULL) != 0) {
        delete m_bufferInUseMutex, m_bufferInUseMutex = 0;
    }
    if (pthread_cond_init(m_bufferFreeCondition, NULL) != 0) {
        delete m_bufferFreeCondition, m_bufferFreeCondition = 0;
    }
}
    
Audio_Queue::~Audio_Queue()
{
    stop();
    
    if (m_audioQueueStarted) {
        if (AudioQueueDispose(m_outAQ, false) != 0) {
            AQ_TRACE("%s: AudioQueueDispose failed!\n", __PRETTY_FUNCTION__);
        }
    }
    m_state = IDLE;
    
    /* free the mutex and condition after the audio queue no longer uses it */
    if (m_bufferInUseMutex) {
        pthread_mutex_destroy(m_bufferInUseMutex);
        delete m_bufferInUseMutex, m_bufferInUseMutex = 0; 
    }
    
    if (m_bufferFreeCondition) {
        pthread_cond_destroy(m_bufferFreeCondition);
        delete m_bufferFreeCondition, m_bufferFreeCondition = 0;
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
    if (!m_audioQueueStarted) {
        return;
    }
    
    AQ_TRACE("%s: enter\n", __PRETTY_FUNCTION__);

    if (AudioQueueFlush(m_outAQ) != 0) {
        AQ_TRACE("%s: AudioQueueFlush failed!\n", __PRETTY_FUNCTION__);
    }
    
    if (AudioQueueStop(m_outAQ, true) != 0) {
        AQ_TRACE("%s: AudioQueueStop failed!\n", __PRETTY_FUNCTION__);
    }
    
    m_audioQueueStarted = false;
    
    AQ_TRACE("%s: leave\n", __PRETTY_FUNCTION__);
}

void Audio_Queue::handlePropertyChange(AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
{
    OSStatus err = noErr;
    
    AQ_TRACE("found property '%lu%lu%lu%lu'\n", (inPropertyID>>24)&255, (inPropertyID>>16)&255, (inPropertyID>>8)&255, inPropertyID&255);
    
    switch (inPropertyID) {
        case kAudioFileStreamProperty_ReadyToProducePackets:
        {
            // the file stream parser is now ready to produce audio packets.
            // get the stream format.
            AudioStreamBasicDescription asbd;
            memset(&asbd, 0, sizeof(asbd));
            UInt32 asbdSize = sizeof(asbd);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &asbd);
            if (err) {
                AQ_TRACE("get kAudioFileStreamProperty_DataFormat\n");
                m_lastError = err;
                break;
            }
            
            // create the audio queue
            err = AudioQueueNewOutput(&asbd, audioQueueOutputCallback, this, NULL, NULL, 0, &m_outAQ);
            if (err) {
                AQ_TRACE("AudioQueueNewOutput\n");
                m_lastError = err;
                break;
            }
            
            // allocate audio queue buffers
            for (unsigned int i = 0; i < AQ_BUFFERS; ++i) {
                err = AudioQueueAllocateBuffer(m_outAQ, AQ_BUFSIZ, &m_audioQueueBuffer[i]);
                if (err) {
                    AQ_TRACE("AudioQueueAllocateBuffer\n");
                    m_lastError = err;
                    break;
                }
            }
            
            setCookiesForStream(inAudioFileStream);
            
            // listen for kAudioQueueProperty_IsRunning
            err = AudioQueueAddPropertyListener(m_outAQ, kAudioQueueProperty_IsRunning, audioQueueIsRunningCallback, this);
            if (err) {
                AQ_TRACE("error in AudioQueueAddPropertyListener");
                m_lastError = err;
                break;
            }
            
            break;
        }
    }
}

void Audio_Queue::handleAudioPackets(UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions)
{
    // this is called by audio file stream when it finds packets of audio
    AQ_TRACE("got data.  bytes: %lu  packets: %lu\n", inNumberBytes, inNumberPackets);
    
    if (inPacketDescriptions) {
        // variable bitrate (VBR) data
        for (int i = 0; i < inNumberPackets; ++i) {
            SInt64 packetOffset = inPacketDescriptions[i].mStartOffset;
            SInt64 packetSize   = inPacketDescriptions[i].mDataByteSize;
            
            // if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
            size_t bufSpaceRemaining = AQ_BUFSIZ - m_bytesFilled;
            
            if (bufSpaceRemaining < packetSize) {
                enqueueBuffer();
            }
            
            // copy data to the audio queue buffer
            AudioQueueBufferRef fillBuf = m_audioQueueBuffer[m_fillBufferIndex];
            memcpy((char*)fillBuf->mAudioData + m_bytesFilled, (const char*)inInputData + packetOffset, packetSize);
            // fill out packet description
            m_packetDescs[m_packetsFilled] = inPacketDescriptions[i];
            m_packetDescs[m_packetsFilled].mStartOffset = m_bytesFilled;
            // keep track of bytes filled and packets filled
            m_bytesFilled += packetSize;
            m_packetsFilled += 1;
            
            // if that was the last free packet description, then enqueue the buffer.
            size_t packetsDescsRemaining = AQ_MAX_PACKET_DESCS - m_packetsFilled;
            if (packetsDescsRemaining == 0) {
                enqueueBuffer();
            }
        }
    } else {
        // constant bitrate (CBR) data
        // if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
        size_t bufSpaceRemaining = AQ_BUFSIZ - m_bytesFilled;
        
        if (bufSpaceRemaining < inNumberBytes) {
            enqueueBuffer();
        }
        
        AudioQueueBufferRef fillBuf = m_audioQueueBuffer[m_fillBufferIndex];
        memcpy((char*)fillBuf->mAudioData + m_bytesFilled, (const char*)inInputData, inNumberBytes);
        // keep track of bytes filled and packets filled
        m_bytesFilled += inNumberBytes;
        m_packetsFilled = 0;
    }
}

/* private */
    
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

void Audio_Queue::startQueueIfNeeded()
{
    if (!m_audioQueueStarted) {
        // start the queue if it has not been started already
        OSStatus err = AudioQueueStart(m_outAQ, NULL);
        if (!err) {
            m_audioQueueStarted = true;
            m_lastError = noErr;
        } else {	
            m_lastError = err;
        }
    }
}

void Audio_Queue::enqueueBuffer()
{
    m_bufferInUse[m_fillBufferIndex] = true;
    
    // enqueue buffer
    AudioQueueBufferRef fillBuf = m_audioQueueBuffer[m_fillBufferIndex];
    fillBuf->mAudioDataByteSize = m_bytesFilled;		
    OSStatus err = AudioQueueEnqueueBuffer(m_outAQ, fillBuf, m_packetsFilled, m_packetDescs);
    if (!err) {
        m_lastError = noErr;
        startQueueIfNeeded();
    } else {
        m_lastError = err;                
    }
    
    waitForFreeBuffer();
}

void Audio_Queue::waitForFreeBuffer()
{
    // go to next buffer
    if (++m_fillBufferIndex >= AQ_BUFFERS) {
       m_fillBufferIndex = 0; 
    }
    // reset bytes filled
    m_bytesFilled = 0;
    // reset packets filled
    m_packetsFilled = 0;
    
    // wait until next buffer is not in use
    AQ_TRACE("->lock\n");
    pthread_mutex_lock(m_bufferInUseMutex); 
    while (m_bufferInUse[m_fillBufferIndex]) {
        AQ_TRACE("waitForFreeBuffer: ... WAITING ...: fillBufferIndex %lu, inuse %s\n", m_fillBufferIndex, (m_bufferInUse[m_fillBufferIndex] ?  "YES" : "NO"));
        pthread_cond_wait(m_bufferFreeCondition, m_bufferInUseMutex);
    }
    pthread_mutex_unlock(m_bufferInUseMutex);
    AQ_TRACE("<-unlock\n");
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
    
// this is called by the audio queue when it has finished decoding our data. 
// The buffer is now free to be reused.
void Audio_Queue::audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    Audio_Queue *audioQueue = static_cast<Audio_Queue*>(inClientData);
    unsigned int bufIndex = audioQueue->findQueueBuffer(inBuffer);
    
    AQ_TRACE("signaling buffer free for inuse %i....\n", bufIndex);
    
    // signal waiting thread that the buffer is free.
    pthread_mutex_lock(audioQueue->m_bufferInUseMutex);
    audioQueue->m_bufferInUse[bufIndex] = false;
    pthread_cond_signal(audioQueue->m_bufferFreeCondition);
    pthread_mutex_unlock(audioQueue->m_bufferInUseMutex);
    
    AQ_TRACE("signal sent!\n");
}

void Audio_Queue::audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    Audio_Queue *audioQueue = static_cast<Audio_Queue*>(inClientData);
    
    UInt32 running;
    UInt32 size;
    OSStatus err = AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &running, &size);
    if (err) {
        AQ_TRACE("error in kAudioQueueProperty_IsRunning");
        audioQueue->setState(IDLE);
        audioQueue->m_lastError = err;
        return;
    }
    if (running) {
        audioQueue->setState(RUNNING);
    } else {
        audioQueue->setState(IDLE);
    }
}    
    
} // namespace astreamer