/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#include "stream_configuration.h"

namespace astreamer {
    
Stream_Configuration::Stream_Configuration()
{
}

Stream_Configuration::~Stream_Configuration()
{
}

Stream_Configuration* Stream_Configuration::configuration()
{
    static Stream_Configuration config;
    return &config;
}
    
}