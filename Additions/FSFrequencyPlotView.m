/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#include "FSFrequencyPlotView.h"

@interface FSFrequencyPlotView ()
- (void)setupCustomInitialisation;
@end

@implementation FSFrequencyPlotView

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupCustomInitialisation];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super initWithCoder:decoder]) {
        [self setupCustomInitialisation];
    }
    return self;
}

- (void)setupCustomInitialisation
{
    self.backgroundColor = [UIColor clearColor];
}

- (void)frequenceAnalyzer:(FSFrequencyDomainAnalyzer *)analyzer levelsAvailable:(float *)levels count:(NSUInteger)count
{
    if (_drawing) {
        return;
    }
    
    _count = MIN(kFSFrequencyPlotViewMaxCount, count);

    memcpy(_levels, levels, sizeof(float) * _count);
    
    [self setNeedsDisplay];
}

- (void)reset
{
    _count = 0;
    
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    if (_count == 0) {
        return;
    }
    
    for (NSUInteger i=0; i < _count; i++) {
        if (_levels[i] < 0 || _levels[i] > 1) {
            NSAssert(false, @"Invalid level: %f", _levels[i]);
        }
    }
    
    _drawing = YES;
    
    const CGFloat height = CGRectGetHeight(self.bounds);
    const CGFloat levelWidth = (int) CGRectGetWidth(self.bounds) / _count;
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetLineWidth(context, 2);
    CGContextSetStrokeColorWithColor(context, [UIColor yellowColor].CGColor);
    
    CGFloat yp = height - (_levels[0] * height);
    
    CGContextMoveToPoint(context, 0, yp);
    
    for (NSUInteger i=1; i < _count; i++) {
        CGFloat x = levelWidth * i;
        CGFloat y = height - (_levels[i] * height);
        
        CGContextAddLineToPoint(context, x, y);
    }
    
    CGContextStrokePath(context);
    
    _drawing = NO;
}

@end
