//
//  NotificationsManager.m
//  Signal
//
//  Created by Frederic Jacobs on 22/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import "NotificationsManager.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "PropertyListPreferences.h"
#import "PushManager.h"
#import "Signal-Swift.h"
#import <AudioToolbox/AudioServices.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TextSecureKitEnv.h>

@interface NotificationsManager ()

@property SystemSoundID newMessageSound;
@property NSMutableDictionary<NSString *, UILocalNotification *> *currentNotifications;

@end

@implementation NotificationsManager

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _currentNotifications = [NSMutableDictionary new];

    NSURL *newMessageURL = [[NSBundle mainBundle] URLForResource:@"NewMessage" withExtension:@"aifc"];
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)newMessageURL, &_newMessageSound);

    return self;
}


#pragma mark - Redphone Calls

/**
 * Notify user for Redphone Call
 */
- (void)notifyUserForCall:(TSCall *)call inThread:(TSThread *)thread {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        // Remove previous notification of call and show missed notification.
        UILocalNotification *notif = [[PushManager sharedManager] closeVOIPBackgroundTask];
        TSContactThread *cThread   = (TSContactThread *)thread;

        if (call.callType == RPRecentCallTypeMissed) {
            if (notif) {
                [[UIApplication sharedApplication] cancelLocalNotification:notif];
            }

            UILocalNotification *notification = [[UILocalNotification alloc] init];
            notification.soundName            = @"NewMessage.aifc";
            if ([[Environment preferences] notificationPreviewType] == NotificationNoNameNoPreview) {
                notification.alertBody = [NSString stringWithFormat:NSLocalizedString(@"MISSED_CALL", nil)];
            } else {
                notification.userInfo = @{Signal_Call_UserInfo_Key : cThread.contactIdentifier};
                notification.category = Signal_CallBack_Category;
                notification.alertBody =
                    [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_MISSED_CALL", nil), [thread name]];
            }

            [[PushManager sharedManager] presentNotification:notification];
        }
    }
}

#pragma mark - Signal Calls

/**
 * Notify user for incoming WebRTC Call
 */
- (void)presentIncomingCall:(SignalCall *)call callerName:(NSString *)callerName
{
    DDLogDebug(@"%@ incoming call from: %@", self.tag, call.remotePhoneNumber);

    UILocalNotification *notification = [UILocalNotification new];
    notification.category = PushManagerCategoriesIncomingCall;
    notification.soundName = @"r.caf";
    NSString *localCallId = call.localId.UUIDString;
    notification.userInfo = @{ PushManagerUserInfoKeysCallLocalId : localCallId };

    PropertyListPreferences *prefs = [Environment getCurrent].preferences;
    NSString *alertMessage;
    switch ([prefs notificationPreviewType]) {
        case NotificationNoNameNoPreview: {
            alertMessage = NSLocalizedString(@"INCOMING_CALL", @"notification body");
            break;
        }
        case NotificationNameNoPreview:
        case NotificationNamePreview: {
            alertMessage = [NSString stringWithFormat:NSLocalizedString(@"INCOMING_CALL_FROM", @"notification body"), callerName];
            break;
        }
    }
    notification.alertBody = [NSString stringWithFormat:@"☎️ %@", alertMessage];

    [self presentNotification:notification identifier:localCallId];
}

/**
 * Notify user for missed WebRTC Call
 */
- (void)presentMissedCall:(SignalCall *)call callerName:(NSString *)callerName
{
    UILocalNotification *notification = [UILocalNotification new];
    notification.category = PushManagerCategoriesMissedCall;
    NSString *localCallId = call.localId.UUIDString;
    notification.userInfo = @{ PushManagerUserInfoKeysCallLocalId : localCallId };

    PropertyListPreferences *prefs = [Environment getCurrent].preferences;
    NSString *alertMessage;
    switch ([prefs notificationPreviewType]) {
        case NotificationNoNameNoPreview: {
            alertMessage = [NSString stringWithFormat:NSLocalizedString(@"MISSED_CALL", @"notification body")];
            break;
        }
        case NotificationNameNoPreview:
        case NotificationNamePreview: {
            alertMessage = [NSString stringWithFormat:NSLocalizedString(@"MSGVIEW_MISSED_CALL", @"notification body"), callerName];
            break;
        }
    }
    notification.alertBody = [NSString stringWithFormat:@"☎️ %@", alertMessage];

    [self presentNotification:notification identifier:localCallId   ];
}

#pragma mark - Signal Messages

- (void)notifyUserForErrorMessage:(TSErrorMessage *)message inThread:(TSThread *)thread {
    NSString *messageDescription = message.description;

    if (([UIApplication sharedApplication].applicationState != UIApplicationStateActive) && messageDescription) {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.userInfo             = @{Signal_Thread_UserInfo_Key : thread.uniqueId};
        notification.soundName            = @"NewMessage.aifc";

        NSString *alertBodyString = @"";

        NSString *authorName = [thread name];
        switch ([[Environment preferences] notificationPreviewType]) {
            case NotificationNamePreview:
            case NotificationNameNoPreview:
                alertBodyString = [NSString stringWithFormat:@"%@: %@", authorName, messageDescription];
                break;
            case NotificationNoNameNoPreview:
                alertBodyString = messageDescription;
                break;
        }
        notification.alertBody = alertBodyString;

        [[PushManager sharedManager] presentNotification:notification];
    } else {
        if ([Environment.preferences soundInForeground]) {
            AudioServicesPlayAlertSound(_newMessageSound);
        }
    }
}

- (void)notifyUserForIncomingMessage:(TSIncomingMessage *)message
                                from:(NSString *)name
                            inThread:(TSThread *)thread
                     contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    NSString *messageDescription = message.description;

    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive && messageDescription) {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        notification.soundName            = @"NewMessage.aifc";

        switch ([[Environment preferences] notificationPreviewType]) {
            case NotificationNamePreview:
                notification.category = Signal_Full_New_Message_Category;
                notification.userInfo =
                    @{Signal_Thread_UserInfo_Key : thread.uniqueId, Signal_Message_UserInfo_Key : message.uniqueId};

                if ([thread isGroupThread]) {
                    NSString *sender = [contactsManager displayNameForPhoneIdentifier:message.authorId];
                    NSString *threadName = [NSString stringWithFormat:@"\"%@\"", name];
                    notification.alertBody =
                        [NSString stringWithFormat:NSLocalizedString(@"APN_MESSAGE_IN_GROUP_DETAILED", nil),
                                                   sender,
                                                   threadName,
                                                   messageDescription];
                } else {
                    notification.alertBody = [NSString stringWithFormat:@"%@: %@", name, messageDescription];
                }
                break;
            case NotificationNameNoPreview: {
                notification.userInfo = @{Signal_Thread_UserInfo_Key : thread.uniqueId};
                if ([thread isGroupThread]) {
                    notification.alertBody =
                        [NSString stringWithFormat:@"%@ \"%@\"", NSLocalizedString(@"APN_MESSAGE_IN_GROUP", nil), name];
                } else {
                    notification.alertBody =
                        [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"APN_MESSAGE_FROM", nil), name];
                }
                break;
            }
            case NotificationNoNameNoPreview:
                notification.alertBody = NSLocalizedString(@"APN_Message", nil);
                break;
            default:
                notification.alertBody = NSLocalizedString(@"APN_Message", nil);
                break;
        }

        [[PushManager sharedManager] presentNotification:notification];
    } else {
        if ([Environment.preferences soundInForeground]) {
            AudioServicesPlayAlertSound(_newMessageSound);
        }
    }
}

#pragma mark - Util

- (void)presentNotification:(UILocalNotification *)notification identifier:(NSString *)identifier
{
    // Replace any existing notification
    // e.g. when an "Incoming Call" notification gets replaced with a "Missed Call" notification.
    if (self.currentNotifications[identifier]) {
        [self cancelNotificationWithIdentifier:identifier];
    }

    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    DDLogDebug(@"%@ presenting notification with identifier: %@", self.tag, identifier);

    self.currentNotifications[identifier] = notification;
}

- (void)cancelNotificationWithIdentifier:(NSString *)identifier
{
    UILocalNotification *notification = self.currentNotifications[identifier];
    if (!notification) {
        DDLogWarn(@"%@ Couldn't cancel notification because none was found with identifier: %@", self.tag, identifier);
        return;
    }
    [self.currentNotifications removeObjectForKey:identifier];

    [[UIApplication sharedApplication] cancelLocalNotification:notification];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
