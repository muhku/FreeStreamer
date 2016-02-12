//
//  AJNotificationView.h
//  AJNotificationViewDemo
//
//  Created by Alberto Jerez on 02/08/12.
//  Copyright (c) 2012 CodeApps. All rights reserved.
//
//Copyright © 2012 Alberto Jerez - CodeApps
//
//Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”),
//to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
//and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//IN THE SOFTWARE.

#import <UIKit/UIKit.h>

#define RGBA(r,g,b,a) [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a]

typedef enum {
    AJNotificationTypeDefault,
    AJNotificationTypeBlue,
    AJNotificationTypeRed,
    AJNotificationTypeGreen,
    AJNotificationTypeOrange,
    AJNotificationTypeWhite
} AJNotificationType;

typedef enum {
    AJLinedBackgroundTypeDisabled,
    AJLinedBackgroundTypeStatic,
    AJLinedBackgroundTypeAnimated
} AJLinedBackgroundType;

@interface AJNotificationView : UIView

//Show default notification (gray), hide after 2.5 seg
+ (AJNotificationView *)showNoticeInView:(UIView *)view title:(NSString *)title;

//Show default notification (gray)
+ (AJNotificationView *)showNoticeInView:(UIView *)view title:(NSString *)title hideAfter:(NSTimeInterval)hideInterval;

+ (AJNotificationView *)showNoticeInView:(UIView *)view type:(AJNotificationType)type title:(NSString *)title hideAfter:(NSTimeInterval)hideInterval;

+ (AJNotificationView *)showNoticeInView:(UIView *)view type:(AJNotificationType)type title:(NSString *)title linedBackground:(AJLinedBackgroundType)backgroundType hideAfter:(NSTimeInterval)hideInterval;

+ (AJNotificationView *)showNoticeInView:(UIView *)view type:(AJNotificationType)type title:(NSString *)title linedBackground:(AJLinedBackgroundType)backgroundType hideAfter:(NSTimeInterval)hideInterval detailDisclosure:(BOOL)show;

+ (AJNotificationView *)showNoticeInView:(UIView *)view type:(AJNotificationType)type title:(NSString *)title linedBackground:(AJLinedBackgroundType)backgroundType hideAfter:(NSTimeInterval)hideInterval offset:(float)offset;

//Response blocks are called when a user taps on the banner notification
+ (AJNotificationView *)showNoticeInView:(UIView *)view type:(AJNotificationType)type title:(NSString *)title linedBackground:(AJLinedBackgroundType)backgroundType hideAfter:(NSTimeInterval)hideInterval response:(void (^)(void))response;

+ (AJNotificationView *)showNoticeInView:(UIView *)view type:(AJNotificationType)type title:(NSString *)title linedBackground:(AJLinedBackgroundType)backgroundType hideAfter:(NSTimeInterval)hideInterval offset:(float)offset delay:(NSTimeInterval)delayInterval response:(void (^)(void))response;

+ (AJNotificationView *)showNoticeInView:(UIView *)view type:(AJNotificationType)type title:(NSString *)title linedBackground:(AJLinedBackgroundType)backgroundType hideAfter:(NSTimeInterval)hideInterval offset:(float)offset delay:(NSTimeInterval)delayInterval detailDisclosure:(BOOL)show response:(void (^)(void))response;

//Hide
- (void)hide;
- (UIFont *)titleFont;

+ (void)hideCurrentNotificationView;

+ (void)hideCurrentNotificationViewAndClearQueue;

+ (void)clearQueue;

@end