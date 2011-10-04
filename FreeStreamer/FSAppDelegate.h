/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011 Matias Muhonen <mmu@iki.fi>
 * See the file ''LICENSE'' for using the code.
 */

#import <UIKit/UIKit.h>

@class FSDAO;
@class FSAudioController;

@interface FSAppDelegate : UIResponder <UIApplicationDelegate> {
    UIWindow *_window;
    UINavigationController *_navigationController;
    FSDAO *_dao;
    FSAudioController *_audioController;
}

@property (nonatomic,retain) IBOutlet UIWindow *window;
@property (nonatomic,retain) IBOutlet UINavigationController *navigationController;
@property (nonatomic,readonly) FSDAO *dao;
@property (nonatomic,readonly) FSAudioController *audioController;

@end
