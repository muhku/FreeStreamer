/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <FreeStreamer/FreeStreamer.h>

@protocol FSFrequencyDomainAnalyzerDelegate;

@interface FSFrequencyDomainAnalyzer : NSObject <FSPCMAudioStreamDelegate> {
    BOOL _enabled;
}

@property (nonatomic,unsafe_unretained) IBOutlet id<FSFrequencyDomainAnalyzerDelegate> delegate;
@property (nonatomic,assign) BOOL enabled;
@property (nonatomic,assign) BOOL shouldExit;

- (void)audioStream:(FSAudioStream *)audioStream samplesAvailable:(AudioBufferList *)samples frames:(UInt32)frames description: (AudioStreamPacketDescription)description;

@end

@protocol FSFrequencyDomainAnalyzerDelegate <NSObject>

@optional
- (void)frequenceAnalyzer:(FSFrequencyDomainAnalyzer *)analyzer levelsAvailable:(float *)levels count:(NSUInteger)count;
@end
