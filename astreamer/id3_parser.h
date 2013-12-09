/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#ifndef ASTREAMER_ID3_PARSER_H
#define ASTREAMER_ID3_PARSER_H

#include <string>
#include <map>

#import <CFNetwork/CFNetwork.h>

namespace astreamer {

class ID3_Parser_Delegate;
class ID3_Parser_Private;

class ID3_Parser {
public:
    ID3_Parser();
    ~ID3_Parser();
    
    void reset();
    bool wantData();
    void feedData(UInt8 *data, UInt32 numBytes);
    
    ID3_Parser_Delegate *m_delegate;
    
private:
    ID3_Parser_Private *m_private;
};

class ID3_Parser_Delegate {
public:
    virtual void id3metaDataAvailable(std::map<std::wstring,std::wstring> metaData) = 0;
};
    
} // namespace astreamer

#endif // ASTREAMER_ID3_PARSER_H
