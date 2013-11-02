/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2013 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "FSAudioController.h"

@interface FSXPlayerViewController : NSViewController {
    BOOL _paused;
    FSAudioController *_audioController;
}

@property (nonatomic,readonly) FSAudioController *audioController;
@property (nonatomic,strong) IBOutlet NSTextField *urlTextField;
@property (nonatomic,strong) IBOutlet NSTextFieldCell *stateTextFieldCell;
@property (nonatomic,strong) IBOutlet NSButton *playButton;
@property (nonatomic,strong) IBOutlet NSButton *pauseButton;

- (IBAction)playFromUrl:(id)sender;
- (IBAction)pause:(id)sender;

@end
