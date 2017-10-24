/*
 * This file is part of the FreeStreamer project,
 * (C)Copyright 2011-2018 Matias Muhonen <mmu@iki.fi> 穆马帝
 * See the file ''LICENSE'' for using the code.
 *
 * https://github.com/muhku/FreeStreamer
 */

#import <UIKit/UIKit.h>

/**
 * The application delegate of the iOS example application.
 */
@interface FSAppDelegate : UIResponder <UIApplicationDelegate> {
}

/**
 * Reference to a window.
 */
@property (nonatomic,strong) IBOutlet UIWindow *window;
/**
 * Reference to a navigation controller.
 */
@property (nonatomic,strong) IBOutlet UINavigationController *navigationController;

- (void)resetBackground;

@end
