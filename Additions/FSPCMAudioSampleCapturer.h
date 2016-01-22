/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2016 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#include "FSAudioStream.h"

@interface FSPCMAudioSampleCapturer : NSObject <FSPCMAudioStreamDelegate> {
}

@property (nonatomic,assign) NSString *outputFile;
@property (nonatomic,assign) AudioFileTypeID captureType;

- (void)audioStream:(FSAudioStream *)audioStream samplesAvailable:(AudioBufferList)samples description: (AudioStreamPacketDescription)description;

@end
