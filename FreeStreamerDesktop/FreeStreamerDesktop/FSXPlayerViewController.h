/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#include "FSAudioController.h"

/**
 * The player view controller of the OS X example application.
 *
 * The view allows the user to control the player. See the
 * playFromUrl: and pause: actions.
 */
@interface FSXPlayerViewController : NSViewController {
    BOOL _paused;
    BOOL _record;
    FSAudioController *_audioController;
    NSTimer *_progressUpdateTimer;
}

/**
 * Reference to the audio controller.
 */
@property (nonatomic,readonly) FSAudioController *audioController;
/**
 * Reference to the URL text field.
 */
@property (nonatomic,strong) IBOutlet NSTextField *urlTextField;
/**
 * Reference to the state text field.
 */
@property (nonatomic,strong) IBOutlet NSTextFieldCell *stateTextFieldCell;
/**
 * Reference to the progress text field.
 */
@property (nonatomic,strong) IBOutlet NSTextFieldCell *progressTextFieldCell;
/**
 * Reference to the play button.
 */
@property (nonatomic,strong) IBOutlet NSButton *playButton;
/**
 * Reference to the pause button.
 */
@property (nonatomic,strong) IBOutlet NSButton *pauseButton;

/**
 * An action for starting the playback of the stream.
 *
 * @param sender The sender of the action.
 */
- (IBAction)playFromUrl:(id)sender;
/**
 * An action for pausing the playback of the stream.
 *
 * @param sender The sender of the action.
 */
- (IBAction)pause:(id)sender;
/**
 * An action for recording the output the stream to a file.
 *
 * @param sender The sender of the action.
 */
- (IBAction)record:(id)sender;
@end
