/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#ifndef ASTREAMER_STREAM_CONFIGURATION_H
#define ASTREAMER_STREAM_CONFIGURATION_H

namespace astreamer {
    
struct Stream_Configuration {
    unsigned bufferCount;
    unsigned bufferSize;
    unsigned maxPacketDescs;
    unsigned decodeQueueSize;
    unsigned httpConnectionBufferSize;
    double outputSampleRate;
    long outputNumChannels;
    
    static Stream_Configuration *configuration();
    
private:
    Stream_Configuration();
    ~Stream_Configuration();
    
    Stream_Configuration(const Stream_Configuration&);
    Stream_Configuration& operator=(const Stream_Configuration&);
};
    
} // namespace astreamer

#endif // ASTREAMER_STREAM_CONFIGURATION_H