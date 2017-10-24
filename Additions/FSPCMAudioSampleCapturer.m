/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSPCMAudioSampleCapturer.h"

#import <AVFoundation/AVFoundation.h>

@interface FSPCMAudioSampleCapturer () {
@private
    ExtAudioFileRef _audioFile;
    NSString *_outputFile;
    NSURL *_urlRef;
    BOOL _initialized;
}
@end

@implementation FSPCMAudioSampleCapturer

- (id)init
{
    if (self = [super init]) {
        _captureType = kAudioFileCAFType;
    }
    return self;
}

- (void)dealloc
{
    if (_initialized) {
        ExtAudioFileDispose(_audioFile);
    }
}

- (void)setOutputFile:(NSString *)outputFile
{
    @synchronized(self) {
        if (!outputFile) {
            return;
        }
        
        if ([outputFile isEqual:_outputFile]) {
            return;
        }
        
        _outputFile = [outputFile copy];
        
        _urlRef = CFBridgingRelease(CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                (__bridge  CFStringRef)_outputFile,
                                                kCFURLPOSIXPathStyle,
                                                false));
        
        if (_initialized) {
            ExtAudioFileDispose(_audioFile);
        }
        
        AudioStreamBasicDescription dstFormat;
        
        memset(&dstFormat, 0, sizeof dstFormat);
        
        dstFormat.mSampleRate = (UInt32)[AVAudioSession sharedInstance].sampleRate;
        dstFormat.mFormatID = kAudioFormatLinearPCM;
        dstFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
        dstFormat.mBytesPerPacket = 4;
        dstFormat.mFramesPerPacket = 1;
        dstFormat.mBytesPerFrame = 4;
        dstFormat.mChannelsPerFrame = 2;
        dstFormat.mBitsPerChannel = 16;
        
        OSStatus result = ExtAudioFileCreateWithURL((__bridge CFURLRef _Nonnull)(_urlRef), _captureType, &dstFormat, NULL, kAudioFileFlags_EraseFile, &_audioFile);
        
        if (result == noErr) {
            _initialized = YES;
        } else {
            _initialized = NO;
            
#if defined(DEBUG) || (TARGET_IPHONE_SIMULATOR)
            NSLog(@"FSPCMAudioSampleCapturer: Error: ExtAudioFileCreateWithURL: %@", _urlRef);
#endif
        }
    }
}

- (NSString *)outputFile
{
    @synchronized(self) {
        if (_outputFile) {
            return [_outputFile copy];
        }
        return nil;
    }
}

- (void)audioStream:(FSAudioStream *)audioStream samplesAvailable:(AudioBufferList *)samples frames:(UInt32)frames description: (AudioStreamPacketDescription)description
{
    @synchronized(self) {
        if (_initialized) {
            ExtAudioFileWriteAsync(_audioFile, frames, samples);
        }
    }
}

@end
