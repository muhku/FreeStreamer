/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * Part of the code in this file has been rewritten from
 * the AudioFileStreamExample / afsclient.cpp
 * example, Copyright © 2007 Apple Inc.
 */

#ifndef ASTREAMER_AUDIO_QUEUE_H
#define ASTREAMER_AUDIO_QUEUE_H

#include <pthread.h> /* pthread_*() */
#include <AudioToolbox/AudioToolbox.h> /* AudioFileStreamID */

namespace astreamer {
    
class Audio_Queue_Delegate;
	
class Audio_Queue {
public:
    Audio_Queue_Delegate *m_delegate;
    
    static const size_t AQ_BUFFERS = 16;            // number of audio queue buffers we allocate
    static const size_t AQ_BUFSIZ = 2048;           // number of bytes in each audio queue buffer
    static const size_t AQ_MAX_PACKET_DESCS = 512;  // number of packet descriptions in our array
    
    enum State {
        IDLE,
        RUNNING,
        PAUSED
    };
    
    Audio_Queue();
    virtual ~Audio_Queue();
    
    void handlePropertyChange(AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags);
    void handleAudioPackets(UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions);
    
    void pause();
    void stop();
	
private:
    
    State m_state;
    
    AudioQueueRef m_outAQ;                                           // the audio queue
    
    AudioQueueBufferRef m_audioQueueBuffer[AQ_BUFFERS];              // audio queue buffers	
    AudioStreamPacketDescription m_packetDescs[AQ_MAX_PACKET_DESCS]; // packet descriptions for enqueuing audio
    
    size_t m_fillBufferIndex;                                        // the index of the audioQueueBuffer that is being filled
    size_t m_bytesFilled;                                            // how many bytes have been filled
    size_t m_packetsFilled;                                          // how many packets have been filled
    
    bool m_audioQueueStarted;                                        // flag to indicate that the queue has been started
    bool m_bufferInUse[AQ_BUFFERS];                                  // flags to indicate that a buffer is still in use
    pthread_mutex_t *m_bufferInUseMutex;                             // a mutex to protect the inuse flags
    pthread_cond_t *m_bufferFreeCondition;                           // a condition varable for handling the inuse flags
    
    OSStatus m_lastError;

    void setCookiesForStream(AudioFileStreamID inAudioFileStream);
    void setState(State state);
    void startQueueIfNeeded();
    void enqueueBuffer();
    void waitForFreeBuffer();
    int findQueueBuffer(AudioQueueBufferRef inBuffer);
    
    static void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer);
    static void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ, AudioQueuePropertyID inID);
};
    
class Audio_Queue_Delegate {
public:
    virtual void audioQueueStateChanged(Audio_Queue::State state) = 0;
};

} // namespace astreamer

#endif // ASTREAMER_AUDIO_QUEUE_H