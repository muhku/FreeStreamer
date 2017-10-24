/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import <FreeStreamer/FreeStreamer.h>

@interface FSPCMAudioSampleCapturer : NSObject <FSPCMAudioStreamDelegate> {
}

@property (nonatomic,assign) NSString *outputFile;
@property (nonatomic,assign) AudioFileTypeID captureType;

- (void)audioStream:(FSAudioStream *)audioStream samplesAvailable:(AudioBufferList *)samples frames:(UInt32)frames description: (AudioStreamPacketDescription)description;

@end
