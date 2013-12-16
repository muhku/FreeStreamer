/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#ifndef ASTREAMER_HTTP_STREAM_H
#define ASTREAMER_HTTP_STREAM_H

#import <CFNetwork/CFNetwork.h>
#import <string>
#import <vector>
#import <map>
#import "id3_parser.h"

namespace astreamer {

class HTTP_Stream_Delegate;
    
struct HTTP_Stream_Position {
    size_t start;
    size_t end;
};

class HTTP_Stream : public ID3_Parser_Delegate {
private:
    
    HTTP_Stream(const HTTP_Stream&);
    HTTP_Stream& operator=(const HTTP_Stream&);
    
    static const size_t STREAM_BUFSIZ;
    
    static CFStringRef httpRequestMethod;
    static CFStringRef httpUserAgentHeader;
    static CFStringRef httpUserAgentValue;
    static CFStringRef httpRangeHeader;
    static CFStringRef icyMetaDataHeader;
    static CFStringRef icyMetaDataValue;
    
    CFURLRef m_url;
    CFReadStreamRef m_readStream;
    bool m_scheduledInRunLoop;
    HTTP_Stream_Position m_position;
    
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
    
    std::vector<UInt8> m_icyMetaData;
    
    /* Read buffers */
    UInt8 *m_httpReadBuffer;
    UInt8 *m_icyReadBuffer;
    
    ID3_Parser *m_id3Parser;
    
    CFReadStreamRef createReadStream(CFURLRef url);
    void parseHttpHeadersIfNeeded(UInt8 *buf, CFIndex bufSize);
    void parseICYStream(UInt8 *buf, CFIndex bufSize);
    CFStringRef createMetaDataStringWithMostReasonableEncoding(const UInt8 *bytes, CFIndex numBytes);
    
    static void readCallBack(CFReadStreamRef stream, CFStreamEventType eventType, void *clientCallBackInfo);

public:
    
    HTTP_Stream_Delegate *m_delegate;
    
    HTTP_Stream();
    virtual ~HTTP_Stream();
    
    HTTP_Stream_Position position();
    
    std::string contentType();
    size_t contentLength();
    
    bool open();
    bool open(const HTTP_Stream_Position& position);
    void close();
    
    void setScheduledInRunLoop(bool scheduledInRunLoop);
    
    void setUrl(CFURLRef url);
    
    /* ID3_Parser_Delegate */
    void id3metaDataAvailable(std::map<CFStringRef,CFStringRef> metaData);
};

class HTTP_Stream_Delegate {
public:
    virtual void streamIsReadyRead() = 0;
    virtual void streamHasBytesAvailable(UInt8 *data, UInt32 numBytes) = 0;
    virtual void streamEndEncountered() = 0;
    virtual void streamErrorOccurred() = 0;
    virtual void streamMetaDataAvailable(std::map<CFStringRef,CFStringRef> metaData) = 0;
};

} // namespace astreamer

#endif // ASTREAMER_HTTP_STREAM_H