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

@property (nonatomic,strong) IBOutlet UIWindow *window;
@property (nonatomic,strong) IBOutlet UINavigationController *navigationController;
@property (weak, nonatomic,readonly) FSDAO *dao;
@property (weak, nonatomic,readonly) FSAudioController *audioController;

@end
