/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2014 Matias Muhonen.
 * See the file ''LICENSE'' for using the code.
 */

#include "FSFrequencyDomainAnalyzer.h"

#define kFSFrequencyPlotViewMaxCount 64

@interface FSFrequencyPlotView : UIView <FSFrequencyDomainAnalyzerDelegate> {
    float _levels[kFSFrequencyPlotViewMaxCount];
    NSUInteger _count;
    BOOL _drawing;
}

- (void)frequenceAnalyzer:(FSFrequencyDomainAnalyzer *)analyzer levelsAvailable:(float *)levels count:(NSUInteger)count;
- (void)reset;

@end
