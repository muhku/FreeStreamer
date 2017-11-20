/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import "FSFrequencyDomainAnalyzer.h"

#import <AVFoundation/AVFoundation.h>
#include <Accelerate/Accelerate.h>

// Note: code has been adapted from https://github.com/douban/DOUAudioStreamer/blob/master/src/DOUAudioAnalyzer.m

/*
 *  DOUAudioStreamer - A Core Audio based streaming audio player for iOS/Mac:
 *
 *      https://github.com/douban/DOUAudioStreamer
 *
 *  Copyright 2013 Douban Inc.  All rights reserved.
 *
 *  Use and distribution licensed under the BSD license.  See
 *  the LICENSE file for full text.
 *
 *  Authors:
 *      Chongyu Zhu <lembacon@gmail.com>
 *
 */

#define kSFrequencyDomainAnalyzerSampleCount   1024
#define kSFrequencyDomainAnalyzerLevelCount    20

@interface FSFrequencyDomainAnalyzer () {
@private
    NSThread *_worker;

    size_t _log2Count;
    float _hammingWindow[kSFrequencyDomainAnalyzerSampleCount / 2];

    DSPSplitComplex _complexSplit;
    FFTSetup _fft;

    BOOL _bufferModified;

    int16_t _sampleBuffer[kSFrequencyDomainAnalyzerSampleCount];

    struct {
        float sample[kSFrequencyDomainAnalyzerSampleCount];
        float left[kSFrequencyDomainAnalyzerSampleCount / 2];
        float right[kSFrequencyDomainAnalyzerSampleCount / 2];
    } _vectors;

    struct {
        float real[kSFrequencyDomainAnalyzerSampleCount / 2];
        float imag[kSFrequencyDomainAnalyzerSampleCount / 2];
    } _complexSplitBuffer;

    struct {
        float left[kSFrequencyDomainAnalyzerLevelCount];
        float right[kSFrequencyDomainAnalyzerLevelCount];
        float overall[kSFrequencyDomainAnalyzerLevelCount];
    } _levels;
}

- (void)processorMainLoop;
- (void)processSamples:(const int16_t *)samples;
- (void)analyzeChannel:(const float *)vectors toLevels:(float *)levels;

@end

@implementation FSFrequencyDomainAnalyzer

/*
 * ================================================================
 * PUBLIC
 * ================================================================
 */

- (id)init
{
    if (self = [super init]) {
       _worker = [[NSThread alloc] initWithTarget:self
                                         selector:@selector(processorMainLoop)
                                           object:nil];

        _log2Count = (size_t)lrintf(log2f(kSFrequencyDomainAnalyzerSampleCount / 2));
        vDSP_hamm_window(_hammingWindow, kSFrequencyDomainAnalyzerSampleCount / 2, 0);

        _complexSplit.realp = _complexSplitBuffer.real;
        _complexSplit.imagp = _complexSplitBuffer.imag;

        _fft = vDSP_create_fftsetup(_log2Count, kFFTRadix2);
    }
    return self;
}

- (void)dealloc
{
    self.shouldExit = YES;

    vDSP_destroy_fftsetup(_fft);
}

- (void)audioStream:(FSAudioStream *)audioStream samplesAvailable:(AudioBufferList *)samples frames:(UInt32)frames description: (AudioStreamPacketDescription)description
{
   @synchronized (self) {
       if (!_enabled) {
           return;
       }
       
       if (self.shouldExit) {
           return;
       }

       /*
        * Start the worker thread, if not yet started.
        */
       if (![_worker isExecuting]) {
           [_worker start];
       }
       
       NSUInteger count = description.mDataByteSize / sizeof(int16_t);

       const size_t bufferSize = sizeof(int16_t) * MIN(kSFrequencyDomainAnalyzerSampleCount, count);
       
       memcpy(_sampleBuffer, samples->mBuffers[0].mData, bufferSize);
       
       const size_t diff = sizeof(_sampleBuffer) - bufferSize;
       
       if (diff > 0) {
           memset(_sampleBuffer + (sizeof(_sampleBuffer) - diff), 0, diff);
       }

      /*
       * Notify the thread that it should process the buffer.
       */
       _bufferModified = YES;
    }
}

/*
 * ================================================================
 * PROPERTIES
 * ================================================================
 */

- (void)setEnabled:(BOOL)enabled
{
    @synchronized (self) {
        if (enabled == _enabled) {
            return;
        }
        
        _enabled = enabled;
    }
}

- (BOOL)enabled
{
    @synchronized (self) {
        return _enabled;
    }
}

/*
 * ================================================================
 * PRIVATE
 * ================================================================
 */

- (void)processorMainLoop
{
    BOOL dispatchLevels = NO;
    do {
        @synchronized (self) {
            if (_bufferModified) {
                
                [self processSamples:_sampleBuffer];
                
                _bufferModified = NO;
                
                dispatchLevels = YES;
            }
        }
        
        if (dispatchLevels && [self.delegate respondsToSelector:@selector(frequenceAnalyzer:levelsAvailable:count:)]) {
            __weak FSFrequencyDomainAnalyzer *weakSelf = self;

            //respect hardware io buffer duration time
            double bufferDuration = [[AVAudioSession sharedInstance] IOBufferDuration];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, bufferDuration * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                FSFrequencyDomainAnalyzer *strongSelf = weakSelf;
                
                // Execute on the main thread
                [self.delegate frequenceAnalyzer:self levelsAvailable:strongSelf->_levels.overall count:kSFrequencyDomainAnalyzerLevelCount];
            });
            
            dispatchLevels = NO;
        }
        
        [NSThread sleepForTimeInterval:.01];
    } while (!self.shouldExit);
}

- (void)processSamples:(const int16_t *)samples
{
      // Split stereo samples to left and right channels
      static const float scale = INT16_MAX;
      vDSP_vflt16((int16_t *)samples, 1, _vectors.sample, 1, kSFrequencyDomainAnalyzerSampleCount);
      vDSP_vsdiv(_vectors.sample, 1, (float *)&scale, _vectors.sample, 1, kSFrequencyDomainAnalyzerSampleCount);

      DSPSplitComplex complexSplit;
      complexSplit.realp = _vectors.left;
      complexSplit.imagp = _vectors.right;

      vDSP_ctoz((const DSPComplex *)_vectors.sample, 2, &complexSplit, 1, kSFrequencyDomainAnalyzerSampleCount / 2);

      [self analyzeChannel:_vectors.left toLevels:_levels.left];
      [self analyzeChannel:_vectors.right toLevels:_levels.right];

      // Combine left and right channels
      static const float scale2 = 2.0f;
      vDSP_vadd(_levels.left, 1, _levels.right, 1, _levels.overall, 1, kSFrequencyDomainAnalyzerLevelCount);
      vDSP_vsdiv(_levels.overall, 1, (float *)&scale2, _levels.overall, 1, kSFrequencyDomainAnalyzerLevelCount);

      // Normalize levels between [0,1]
      static const float min = 0.0f;
      static const float max = 1.0f;
      vDSP_vclip(_levels.overall, 1, (float *)&min, (float *)&max, _levels.overall, 1, kSFrequencyDomainAnalyzerLevelCount);
}

- (void)analyzeChannel:(const float *)vectors toLevels:(float *)levels
{
    // Split interleaved complex vectors
    vDSP_vmul(vectors, 1, _hammingWindow, 1, (float *)vectors, 1, kSFrequencyDomainAnalyzerSampleCount / 2);
    vDSP_ctoz((const DSPComplex *)vectors, 2, &_complexSplit, 1, kSFrequencyDomainAnalyzerSampleCount / 4);

    // Perform forward DFT with vectors
    vDSP_fft_zrip(_fft, &_complexSplit, 1, _log2Count, kFFTDirection_Forward);
    vDSP_zvabs(&_complexSplit, 1, (float *)vectors, 1, kSFrequencyDomainAnalyzerSampleCount / 4);

    static const float scale = 0.5f;
    vDSP_vsmul(vectors, 1, &scale, (float *)vectors, 1, kSFrequencyDomainAnalyzerSampleCount / 4);

    // Normalize vectors
    static const int size = kSFrequencyDomainAnalyzerSampleCount / 8;
    vDSP_vsq(vectors, 1, (float *)vectors, 1, size);
    vvlog10f((float *)vectors, vectors, &size);

    static const float multiplier = 1.0f / 16.0f;
    const float increment = sqrtf(multiplier);
    vDSP_vsmsa((float *)vectors, 1, (float *)&multiplier, (float *)&increment, (float *)vectors, 1, kSFrequencyDomainAnalyzerSampleCount / 4);

    for (size_t i = 0; i < kSFrequencyDomainAnalyzerLevelCount; ++i) {
       levels[i] = vectors[1 + ((size - 1) / kSFrequencyDomainAnalyzerLevelCount) * i];
    }
}

@end
