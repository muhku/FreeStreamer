/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#include "id3_parser.h"

#include <vector>
#include <sstream>

namespace astreamer {
    
enum ID3_Parser_State {
    ID3_Parser_State_Initial = 0,
    ID3_Parser_State_Parse_Frames,
    ID3_Parser_State_Tag_Parsed,
    ID3_Parser_State_Not_Valid_Tag
};
    
/*
 * =======================================
 * Private class
 * =======================================
 */
    
class ID3_Parser_Private {
public:
    ID3_Parser_Private();
    ~ID3_Parser_Private();
    
    bool wantData();
    void feedData(UInt8 *data, UInt32 numBytes);
    void setState(ID3_Parser_State state);
    void reset();
    
    bool frameNameMatches(const char *frameName, UInt32 position);
    CFStringRef parseContent(UInt32 framesize, UInt32 pos, CFStringEncoding encoding);
    
    ID3_Parser *m_parser;
    ID3_Parser_State m_state;
    UInt32 m_bytesReceived;
    UInt32 m_tagSize;
    bool m_usesUnsynchronisation;
    bool m_usesExtendedHeader;
    
    std::vector<UInt8> m_tagData;
};
    
/*
 * =======================================
 * Private class implementation
 * =======================================
 */
    
ID3_Parser_Private::ID3_Parser_Private() :
    m_parser(0),
    m_state(ID3_Parser_State_Initial),
    m_bytesReceived(0),
    m_tagSize(0),
    m_usesUnsynchronisation(false),
    m_usesExtendedHeader(false)
{
}
    
ID3_Parser_Private::~ID3_Parser_Private()
{
}
    
bool ID3_Parser_Private::wantData()
{
    if (m_state == ID3_Parser_State_Tag_Parsed) {
        return false;
    }
    if (m_state == ID3_Parser_State_Not_Valid_Tag) {
        return false;
    }
    
    return true;
}
    
void ID3_Parser_Private::feedData(UInt8 *data, UInt32 numBytes)
{
    if (!wantData()) {
        return;
    }
    
    m_bytesReceived += numBytes;
    
    for (CFIndex i=0; i < numBytes; i++) {
        m_tagData.push_back(data[i]);
    }
    
    bool enoughBytesToParse = true;
    
    while (enoughBytesToParse) {
        switch (m_state) {
            case ID3_Parser_State_Initial: {
                // Do we have enough bytes to determine if this is an ID3 tag or not?
                if (m_bytesReceived <= 9) {
                    enoughBytesToParse = false;
                    break;
                }
                
                if (!(m_tagData[0] == 'I' &&
                    m_tagData[1] == 'D' &&
                    m_tagData[2] == '3')) {
                    // Does not begin with the tag header; not an ID3 tag
                    setState(ID3_Parser_State_Not_Valid_Tag);
                    enoughBytesToParse = false;
                    break;
                }
                
                UInt8 majorVersion = m_tagData[3];
                // Currently support only id3v2.3
                if (majorVersion != 3) {
                    setState(ID3_Parser_State_Not_Valid_Tag);
                    enoughBytesToParse = false;
                    break;
                }
                
                // Ignore the revision
                
                // Parse the flags
                
                if ((m_tagData[5] & 0x80) != 0) {
                    m_usesUnsynchronisation = true;
                } else if ((m_tagData[5] & 0x40) != 0) {
                    m_usesExtendedHeader = true;
                }
                
                m_tagSize = (m_tagData[9] & 0xFF) | ((m_tagData[8] & 0xFF) << 7 ) | ((m_tagData[7] & 0xFF) << 14);
                
                if (m_tagSize > 0) {
                    setState(ID3_Parser_State_Parse_Frames);
                    break;
                }
                
                setState(ID3_Parser_State_Not_Valid_Tag);
                enoughBytesToParse = false;
                break;
            }
                
            case ID3_Parser_State_Parse_Frames: {
                // Do we have enough data to parse the frames?
                if (m_tagData.size() < m_tagSize) {
                    enoughBytesToParse = false;
                    break;
                }
                
                UInt32 pos = 10;
                
                // Do we have an extended header? If we do, skip it
                if (m_usesExtendedHeader) {
                    UInt32 extendedHeaderSize = (m_tagData[pos] << 21 |
                                                 m_tagData[pos+1] << 14 |
                                                 m_tagData[pos+2] << 7 |
                                                 m_tagData[pos+3]);
                    
                    if (pos + extendedHeaderSize > m_tagData.size()) {
                        setState(ID3_Parser_State_Not_Valid_Tag);
                        enoughBytesToParse = false;
                        break;
                    }
                    
                    pos += extendedHeaderSize;
                }
                
                while (pos < m_tagData.size()) {
                    UInt32 framesize = (m_tagData[pos+7] & 0xFF) |
                                        ((m_tagData[pos+6] & 0xFF) << 8) |
                                        ((m_tagData[pos+5] & 0xFF) << 16) |
                                        ((m_tagData[pos+4] & 0xFF) << 24);
                    if (framesize == 0) {
                        setState(ID3_Parser_State_Not_Valid_Tag);
                        enoughBytesToParse = false;
                        break;
                    }
                    
                    CFStringEncoding encoding;
                    
                    if (m_tagData[pos+10] == 0) {
                        encoding = kCFStringEncodingISOLatin1;
                    } else if (m_tagData[pos+10] == 3) {
                        encoding = kCFStringEncodingUTF8;
                    } else {
                        encoding = kCFStringEncodingUTF16;
                    }
                    
                    if (frameNameMatches("TIT2", pos)) {
                        CFStringRef content = parseContent(framesize, pos, encoding);
                        
                        const char *str = CFStringGetCStringPtr(content, kCFStringEncodingUTF8);
                        if (str) {
                            std::stringstream metaData;
                            metaData << "StreamTitle='";
                            metaData << str;
                            metaData << "';";
                            
                            if (m_parser->m_delegate) {
                                m_parser->m_delegate->id3metaDataAvailable(metaData.str());
                            }
                        }
                        CFRelease(content);
                    }
                    
                    pos += framesize;
                }
                
                setState(ID3_Parser_State_Tag_Parsed);
                enoughBytesToParse = false;
                break;
            }
                
            default:
                enoughBytesToParse = false;
                break;
        }
    }
}

void ID3_Parser_Private::setState(astreamer::ID3_Parser_State state)
{
    m_state = state;
}
    
void ID3_Parser_Private::reset()
{
    m_state = ID3_Parser_State_Initial;
    m_bytesReceived = 0;
    m_tagSize = 0;
    m_usesUnsynchronisation = 0;
    m_usesExtendedHeader = 0;
    
    m_tagData.clear();
}
    
bool ID3_Parser_Private::frameNameMatches(const char *frameName, UInt32 position)
{
    size_t len = strlen(frameName);
    
    for (size_t i=0; i < len; i++) {
        if (m_tagData[position + i] != frameName[i]) {
            return false;
        }
    }
    return true;
}
    
CFStringRef ID3_Parser_Private::parseContent(UInt32 framesize, UInt32 pos, CFStringEncoding encoding)
{
    UInt8* buf = new UInt8[framesize];
    CFIndex bufLen = 0;
    
    for (CFIndex i=0; i < framesize - 1; i++) {
        buf[i] = m_tagData[pos+11+i];
        bufLen++;
    }
    
    delete[] buf;
    
    return CFStringCreateWithBytes(kCFAllocatorDefault,
                                   buf,
                                   bufLen,
                                   encoding,
                                   false);
}
    
/*
 * =======================================
 * ID3_Parser implementation
 * =======================================
 */
    
ID3_Parser::ID3_Parser() :
    m_delegate(0),
    m_private(new ID3_Parser_Private())
{
    m_private->m_parser = this;
}

ID3_Parser::~ID3_Parser()
{
    delete m_private, m_private = 0;
}

void ID3_Parser::reset()
{
    m_private->reset();
}

bool ID3_Parser::wantData()
{
    return m_private->wantData();
}
    
void ID3_Parser::feedData(UInt8 *data, UInt32 numBytes)
{
    m_private->feedData(data, numBytes);
}
    
}