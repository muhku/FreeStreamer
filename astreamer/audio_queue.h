/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 *
 * Part of the code in this file has been rewritten from
 * the AudioFileStreamExample / afsclient.cpp
 * example, Copyright © 2007 Apple Inc.
 */

#ifndef ASTREAMER_AUDIO_QUEUE_H
#define ASTREAMER_AUDIO_QUEUE_H

#include <AudioToolbox/AudioToolbox.h> /* AudioFileStreamID */
#include <vector>

namespace astreamer {
    
class Audio_Queue_Delegate;
struct queued_packet;
	
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
    
    bool initialized();
    
    void handlePropertyChange(AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags);
    void handleAudioPackets(UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions);
    int handlePacket(const void *data, AudioStreamPacketDescription *desc);
    
    void start();
    void pause();
    void stop(bool stopImmediately);
    void stop();
    
    double packetDuration();
    unsigned timePlayedInSeconds();
    unsigned bitrate();
	
private:
    Audio_Queue(const Audio_Queue&);
    Audio_Queue& operator=(const Audio_Queue&);
    
    State m_state;
    
    AudioStreamBasicDescription m_streamDesc;
    AudioQueueRef m_outAQ;                                           // the audio queue
    
    AudioQueueBufferRef m_audioQueueBuffer[AQ_BUFFERS];              // audio queue buffers	
    AudioStreamPacketDescription m_packetDescs[AQ_MAX_PACKET_DESCS]; // packet descriptions for enqueuing audio
    
    UInt32 m_fillBufferIndex;                                        // the index of the audioQueueBuffer that is being filled
    UInt32 m_bytesFilled;                                            // how many bytes have been filled
    UInt32 m_packetsFilled;                                          // how many packets have been filled
    UInt32 m_buffersUsed;                                            // how many buffers are used
    
    UInt32 m_processedPacketsSizeTotal;                              // global packet statistics: total size
    UInt32 m_processedPacketsCount;                                  // global packet statistics: count
    
    bool m_audioQueueStarted;                                        // flag to indicate that the queue has been started
    bool m_bufferInUse[AQ_BUFFERS];                                  // flags to indicate that a buffer is still in use
    bool m_waitingOnBuffer;
    
    struct queued_packet *m_queuedHead;
    struct queued_packet *m_queuedTail;
    
    std::vector<AudioStreamPacketDescription*> m_cbrPacketDescriptions;
    
    OSStatus m_lastError;

    void cleanup();
    void setCookiesForStream(AudioFileStreamID inAudioFileStream);
    void setState(State state);
    int enqueueBuffer();
    int findQueueBuffer(AudioQueueBufferRef inBuffer);
    void enqueueCachedData();
    
    static void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer);
    static void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ, AudioQueuePropertyID inID);
};
    
class Audio_Queue_Delegate {
public:
    virtual void audioQueueStateChanged(Audio_Queue::State state) = 0;
    virtual void audioQueueBuffersEmpty() = 0;
    virtual void audioQueueOverflow() = 0;
    virtual void audioQueueUnderflow() = 0;
    virtual void audioQueueInitializationFailed() = 0;
};

} // namespace astreamer

#endif // ASTREAMER_AUDIO_QUEUE_H