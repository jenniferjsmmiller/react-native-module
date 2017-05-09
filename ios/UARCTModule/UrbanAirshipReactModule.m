/* Copyright 2017 Urban Airship and Contributors */

#import "UrbanAirshipReactModule.h"
#import "AirshipLib.h"
#import "UARCTEventEmitter.h"
#import "UARCTDeepLinkAction.h"

NSString *const NotificationPresentationAlertKey = @"alert";
NSString *const NotificationPresentationBadgeKey = @"badge";
NSString *const NotificationPresentationSoundKey = @"sound";

NSString *const PresentationOptions = @"com.urbanairship.presentation_options";

@implementation UrbanAirshipReactModule

#pragma mark -
#pragma mark Module setup

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

- (void)setBridge:(RCTBridge *)bridge {
    [UARCTEventEmitter shared].bridge = bridge;
}

- (RCTBridge *)bridge {
    return [UARCTEventEmitter shared].bridge;
}

#pragma mark -
#pragma mark Module methods

RCT_EXPORT_METHOD(addListener:(NSString *)eventName) {
    [[UARCTEventEmitter shared] addListener:eventName];
}

RCT_EXPORT_METHOD(removeListeners:(NSInteger)count) {
    [[UARCTEventEmitter shared] removeListeners:count];
}

RCT_EXPORT_METHOD(setUserNotificationsEnabled:(BOOL)enabled) {
    [UAirship push].userPushNotificationsEnabled = enabled;
}

RCT_REMAP_METHOD(isUserNotificationsEnabled,
                 isUserNotificationsEnabled_resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {

    resolve(@([UAirship push].userPushNotificationsEnabled));
}

RCT_REMAP_METHOD(isUserNotificationsOptedIn,
                 isUserNotificationsOptedIn_resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    BOOL optedIn = [UAirship push].authorizedNotificationOptions != 0;
    resolve(@(optedIn));
}

RCT_EXPORT_METHOD(setNamedUser:(NSString *)namedUser) {
    namedUser = [namedUser stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [UAirship namedUser].identifier = namedUser;
}

RCT_EXPORT_METHOD(addTag:(NSString *)tag) {
    [[UAirship push] addTag:tag];
    [[UAirship push] updateRegistration];
}

RCT_EXPORT_METHOD(removeTag:(NSString *)tag) {
    [[UAirship push] removeTag:tag];
    [[UAirship push] updateRegistration];
}

RCT_REMAP_METHOD(getTags,
                 getTags_resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    resolve([UAirship push].tags ?: [NSArray array]);
}

RCT_EXPORT_METHOD(addTag:(NSArray *)tags group:(NSString *)group) {
    [[UAirship push] addTags:tags group:group];
    [[UAirship push] updateRegistration];
}

RCT_EXPORT_METHOD(removeTag:(NSArray *)tags group:(NSString *)group) {
    [[UAirship push] removeTags:tags group:group];
    [[UAirship push] updateRegistration];
}

RCT_EXPORT_METHOD(setAnalyticsEnabled:(BOOL)enabled) {
    [UAirship shared].analytics.enabled = enabled;
}

RCT_REMAP_METHOD(isAnalyticsEnabled,
                 isAnalyticsEnabled_resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@([UAirship shared].analytics.enabled));
}

RCT_REMAP_METHOD(getChannelId,
                 getChannelId_resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    resolve([UAirship push].channelID);
}

RCT_REMAP_METHOD(associateIdentifier,
                 key:(NSString *)key
                 identifier:(NSString *)identifier) {
    UAAssociatedIdentifiers *identifiers = [[UAirship shared].analytics currentAssociatedDeviceIdentifiers];
    [identifiers setIdentifier:identifier forKey:key];
    [[UAirship shared].analytics associateDeviceIdentifiers:identifiers];
}

RCT_EXPORT_METHOD(setLocationEnabled:(BOOL)enabled) {
    [UAirship location].locationUpdatesEnabled = enabled;
}

RCT_REMAP_METHOD(isLocationEnabled,
                 isLocationEnabled_resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@([UAirship location].isLocationUpdatesEnabled));
}

RCT_REMAP_METHOD(isBackgroundLocationAllowed,
                 isBackgroundLocationAllowed_resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@([UAirship location].isBackgroundLocationUpdatesAllowed));
}

RCT_EXPORT_METHOD(setBackgroundLocationAllowed:(BOOL)enabled) {
    [UAirship location].backgroundLocationUpdatesAllowed = enabled;
}

RCT_REMAP_METHOD(runAction,
                 name:(NSString *)name
                 value:(NSString *)value
                 runAction_resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {

    [UAActionRunner runActionWithName:name
                                value:value
                            situation:UASituationManualInvocation
                    completionHandler:^(UAActionResult *actionResult) {

                        NSString *resultString;
                        NSString *code;
                        NSString *errorMessage;
                        NSError *error;

                        switch (actionResult.status) {
                            case UAActionStatusCompleted:
                            {
                                if (actionResult.value) {
                                    //if the action completed with a result value, serialize into JSON
                                    //accepting fragments so we can write lower level JSON values
                                    resultString = [NSJSONSerialization stringWithObject:actionResult.value acceptingFragments:YES error:&error];
                                    // If there was an error serializing, fall back to a string description.
                                    if (error) {
                                        error = error;
                                        UA_LDEBUG(@"Unable to serialize result value %@, falling back to string description", actionResult.value);
                                        // JSONify the result string
                                        resultString = [NSJSONSerialization stringWithObject:[actionResult.value description] acceptingFragments:YES];
                                    }
                                }
                                //in the case where there is no result value, pass null
                                resultString = resultString ?: @"null";
                                break;
                            }
                            case UAActionStatusActionNotFound:
                                errorMessage = [NSString stringWithFormat:@"No action found with name %@, skipping action.", name];
                                code = @"STATUS_ACTION_NOT_FOUND";
                                break;
                            case UAActionStatusError:
                                errorMessage = actionResult.error.localizedDescription;
                                code = @"STATUS_EXECUTION_ERROR";
                                break;
                            case UAActionStatusArgumentsRejected:
                                code = @"STATUS_REJECTED_ARGUMENTS";
                                errorMessage = [NSString stringWithFormat:@"Action %@ rejected arguments.", name];
                                break;
                        }

                        if (actionResult.status == UAActionStatusCompleted) {
                            NSMutableDictionary *result = [NSMutableDictionary dictionary];
                            [result setValue:actionResult.value forKey:@"value"];
                            resolve(actionResult);
                        }

                        if (errorMessage) {
                            reject(code, errorMessage, error);
                        }

                    }];
}

RCT_EXPORT_METHOD(editNamedUserGroups:(NSArray *)operations) {
    UANamedUser *namedUser = [UAirship namedUser];
    for (NSDictionary *operation in [operations objectAtIndex:0]) {
        NSString *group = operation[@"group"];
        if ([operation[@"operationType"] isEqualToString:@"add"]) {
            [namedUser addTags:operation[@"tags"] group:group];
        } else if ([operation[@"operationType"] isEqualToString:@"remove"]) {
            [namedUser removeTags:operation[@"tags"] group:group];
        }
    }

    [namedUser updateTags];
}

RCT_EXPORT_METHOD(editChannelGroups:(NSArray *)operations) {
    for (NSDictionary *operation in [operations objectAtIndex:0]) {
        NSString *group = operation[@"group"];
        if ([operation[@"operationType"] isEqualToString:@"add"]) {
            [[UAirship push] addTags:operation[@"tags"] group:group];
        } else if ([operation[@"operationType"] isEqualToString:@"remove"]) {
            [[UAirship push] removeTags:operation[@"tags"] group:group];
        }
    }

    [[UAirship push] updateRegistration];
}

RCT_EXPORT_METHOD(setForegroundPresentationOptions:(NSDictionary *)options) {
    UNNotificationPresentationOptions presentationOptions = UNNotificationPresentationOptionNone;

    if (options[NotificationPresentationAlertKey] != nil) {
        if ([options[NotificationPresentationAlertKey] boolValue]) {
            presentationOptions = presentationOptions | UNNotificationPresentationOptionAlert;
        }
    }

    if (options[NotificationPresentationBadgeKey] != nil) {
        if ([options[NotificationPresentationBadgeKey] boolValue]) {
            presentationOptions = presentationOptions | UNNotificationPresentationOptionBadge;
        }
    }

    if (options[NotificationPresentationSoundKey] != nil) {
        if ([options[NotificationPresentationSoundKey] boolValue]) {
            presentationOptions = presentationOptions | UNNotificationPresentationOptionSound;
        }
    }

    UA_LDEBUG(@"Foreground presentation options set: %lu", (unsigned long)options);

    [UAirship push].defaultPresentationOptions = presentationOptions;
    [[NSUserDefaults standardUserDefaults] setInteger:presentationOptions forKey:PresentationOptions];
}

@end