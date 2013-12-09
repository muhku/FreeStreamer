/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#include "id3_parser.h"

#include <vector>
#include <sstream>
#include <codecvt>
#include <string>

//#define ID3_DEBUG 1

#if !defined ( ID3_DEBUG)
#define ID3_TRACE(...) do {} while (0)
#else
#define ID3_TRACE(...) printf(__VA_ARGS__)
#endif

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
    
    std::wstring parseContent(UInt32 framesize, UInt32 pos, CFStringEncoding encoding);
    
    ID3_Parser *m_parser;
    ID3_Parser_State m_state;
    UInt32 m_bytesReceived;
    UInt32 m_tagSize;
    bool m_hasFooter;
    bool m_usesUnsynchronisation;
    bool m_usesExtendedHeader;
    std::wstring m_title;
    std::wstring m_performer;
    
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
    m_hasFooter(false),
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
    
    ID3_TRACE("received %i bytes, total bytes %i\n", numBytes, m_bytesReceived);
    
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
                    ID3_TRACE("Not an ID3 tag, bailing out\n");
                    
                    // Does not begin with the tag header; not an ID3 tag
                    setState(ID3_Parser_State_Not_Valid_Tag);
                    enoughBytesToParse = false;
                    break;
                }
                
                UInt8 majorVersion = m_tagData[3];
                // Currently support only id3v2.3
                if (majorVersion != 3) {
                    ID3_TRACE("ID3v2.%i not supported by the parser\n", majorVersion);
                    
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
                } else if ((m_tagData[5] & 0x10) != 0) {
                    m_hasFooter = true;
                }
                
                m_tagSize = (m_tagData[6] << 21) + (m_tagData[7] << 14) + (m_tagData[8] << 7) + m_tagData[9];
                
                if (m_tagSize > 0) {
                    if (m_hasFooter) {
                        m_tagSize += 10;
                    }
                    m_tagSize += 10;
                    
                    ID3_TRACE("tag size: %i\n", m_tagSize);
                    
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
                    ID3_TRACE("Not enough data received for parsing, have %lu bytes, need %i bytes\n",
                              m_tagData.size(),
                              m_tagSize);
                    enoughBytesToParse = false;
                    break;
                }
                
                UInt32 pos = 10;
                
                // Do we have an extended header? If we do, skip it
                if (m_usesExtendedHeader) {
                    UInt32 extendedHeaderSize = ((m_tagData[pos] << 21) |
                                                 (m_tagData[pos+1] << 14) |
                                                 (m_tagData[pos+2] << 7) |
                                                 m_tagData[pos+3]);
                    
                    if (pos + extendedHeaderSize >= m_tagSize) {
                        setState(ID3_Parser_State_Not_Valid_Tag);
                        enoughBytesToParse = false;
                        break;
                    }
                    
                    ID3_TRACE("Skipping extended header, size %i\n", extendedHeaderSize);
                    
                    pos += extendedHeaderSize;
                }
                
                while (pos < m_tagSize) {
                    char frameName[5];
                    frameName[0] = m_tagData[pos];
                    frameName[1] = m_tagData[pos+1];
                    frameName[2] = m_tagData[pos+2];
                    frameName[3] = m_tagData[pos+3];
                    frameName[4] = 0;
                    
                    pos += 4;
                    
                    UInt32 framesize = ((m_tagData[pos] << 21) |
                                        (m_tagData[pos+1] << 14) |
                                        (m_tagData[pos+2] << 7) |
                                        m_tagData[pos+3]);
                    if (framesize == 0) {
                        setState(ID3_Parser_State_Not_Valid_Tag);
                        enoughBytesToParse = false;
                        break;
                    }
                    
                    pos += 6;
                    
                    CFStringEncoding encoding;
                    
                    if (m_tagData[pos] == 3) {
                        encoding = kCFStringEncodingUTF8;
                    } else {
                        // ISO-8859-1 is the default encoding
                        encoding = kCFStringEncodingISOLatin1;
                    }
                    
                    if (!strcmp(frameName, "TIT2")) {
                        m_title = parseContent(framesize, pos + 1, encoding);
                        
                        ID3_TRACE("ID3 title parsed: '%s'\n", m_title.c_str());
                    } else if (!strcmp(frameName, "TPE1")) {
                        m_performer = parseContent(framesize, pos + 1, encoding);
                        
                        ID3_TRACE("ID3 performer parsed: '%s'\n", m_performer.c_str());
                    } else {
                        // Unknown/unhandled frame
                        ID3_TRACE("Unknown/unhandled frame: %s, size %i\n", frameName, framesize);
                    }
                    
                    pos += framesize;
                }
                
                // Push out the metadata
                if (m_parser->m_delegate) {
                    std::map<std::wstring,std::wstring> metadataMap;
                    std::wstringstream info;
                    
                    if (m_performer.length() > 0) {
                        info << m_performer;
                        info << " - ";
                    }
                    
                    info << m_title;
                    
                    metadataMap[L"StreamTitle"] = info.str();
                
                    m_parser->m_delegate->id3metaDataAvailable(metadataMap);
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
    m_hasFooter = false;
    m_usesUnsynchronisation = false;
    m_usesExtendedHeader = false;
    m_title = L"";
    m_performer = L"";
    
    m_tagData.clear();
}
    
std::wstring ID3_Parser_Private::parseContent(UInt32 framesize, UInt32 pos, CFStringEncoding encoding)
{
    std::wstring frameContent;
    UInt8* buf = new UInt8[framesize];
    CFIndex bufLen = 0;
    
    for (CFIndex i=0; i < framesize - 1; i++) {
        buf[i] = m_tagData[pos+i];
        bufLen++;
    }
    
    CFStringRef content = CFStringCreateWithBytes(kCFAllocatorDefault,
                                                   buf,
                                                   bufLen,
                                                   encoding,
                                                   false);
    
    const char *str = CFStringGetCStringPtr(content, kCFStringEncodingUTF8);
    if (str) {
        std::wstring_convert<std::codecvt_utf8_utf16<wchar_t> > converter;
        frameContent = converter.from_bytes(std::string(str));
    }
    
    delete[] buf;
    CFRelease(content);
    
    return frameContent;
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