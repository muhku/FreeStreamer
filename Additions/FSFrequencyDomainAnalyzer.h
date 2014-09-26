/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#include "FSAudioStream.h"

@protocol FSFrequencyDomainAnalyzerDelegate;

@interface FSFrequencyDomainAnalyzer : NSObject <FSPCMAudioStreamDelegate> {
    BOOL _enabled;
}

@property (nonatomic,unsafe_unretained) IBOutlet id<FSFrequencyDomainAnalyzerDelegate> delegate;
@property (nonatomic,assign) BOOL enabled;
@property (nonatomic,assign) BOOL shouldExit;

- (void)audioStream:(FSAudioStream *)audioStream samplesAvailable:(const int16_t *)samples count:(NSUInteger)count;

@end

@protocol FSFrequencyDomainAnalyzerDelegate <NSObject>

@optional
- (void)frequenceAnalyzer:(FSFrequencyDomainAnalyzer *)analyzer levelsAvailable:(float *)levels count:(NSUInteger)count;
@end
