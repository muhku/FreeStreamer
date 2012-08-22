/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#ifndef ASTREAMER_HTTP_STREAM_H
#define ASTREAMER_HTTP_STREAM_H

#import <CFNetwork/CFNetwork.h>
#import <string>
#import <vector>

namespace astreamer {

class HTTP_Stream_Delegate;

class HTTP_Stream {
private:
    
    HTTP_Stream(const HTTP_Stream&);
    HTTP_Stream& operator=(const HTTP_Stream&);
    
    static const size_t STREAM_BUFSIZ;
    
    static CFStringRef httpRequestMethod;
    static CFStringRef httpUserAgentHeader;
    static CFStringRef httpUserAgentValue;
    static CFStringRef icyMetaDataHeader;
    static CFStringRef icyMetaDataValue;
    
    CFURLRef m_url;
    CFReadStreamRef m_readStream;
    bool m_scheduledInRunLoop;
    
    /* HTTP headers */
    bool m_httpHeadersParsed;
    std::string m_contentType;
    size_t m_contentLength;
    
    /* ICY protocol */
    bool m_icyStream;
    bool m_icyHeaderCR;
    bool m_icyHeadersRead;
    bool m_icyHeadersParsed;
    
    std::vector<std::string> m_icyHeaderLines;
    size_t m_icyMetaDataInterval;
    size_t m_dataByteReadCount;
    size_t m_metaDataBytesRemaining;
    
    std::string m_icyMetaData;
    
    /* Read buffers */
    UInt8 *m_httpReadBuffer;
    UInt8 *m_icyReadBuffer;
    
    CFReadStreamRef createReadStream(CFURLRef url);
    void parseHttpHeadersIfNeeded(UInt8 *buf, CFIndex bufSize);
    void parseICYStream(UInt8 *buf, CFIndex bufSize);
    
    static void readCallBack(CFReadStreamRef stream, CFStreamEventType eventType, void *clientCallBackInfo);

public:
    
    HTTP_Stream_Delegate *m_delegate;
    
    HTTP_Stream();
    virtual ~HTTP_Stream();
    
    std::string contentType();
    size_t contentLength();
    
    bool open();
    void close();
    
    void setScheduledInRunLoop(bool scheduledInRunLoop);
    
    void setUrl(CFURLRef url);
};

class HTTP_Stream_Delegate {
public:
    virtual void streamIsReadyRead() = 0;
    virtual void streamHasBytesAvailable(UInt8 *data, CFIndex numBytes) = 0;
    virtual void streamEndEncountered() = 0;
    virtual void streamErrorOccurred() = 0;
    virtual void streamMetaDataAvailable(std::string metaData) = 0;
};

} // namespace astreamer

#endif // ASTREAMER_HTTP_STREAM_H