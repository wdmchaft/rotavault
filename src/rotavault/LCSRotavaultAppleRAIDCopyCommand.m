//
//  LCSRotavaultAppleRAIDCopyCommand.m
//  rotavault
//
//  Created by Lorenz Schori on 20.10.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import "LCSRotavaultAppleRAIDCopyCommand.h"
#import "LCSInitMacros.h"
#import "LCSCommandController.h"
#import "LCSDiskInfoCommand.h"
#import "LCSAppleRAIDListCommand.h"
#import "LCSAppleRAIDAddMemberCommand.h"
#import "LCSAppleRAIDRemoveMemberCommand.h"
#import "LCSAppleRAIDMonitorRebuildCommand.h"
#import "LCSRotavaultError.h"
#import "LCSPropertyListSHA1Hash.h"
#import "NSData+Hex.h"

@interface LCSRotavaultAppleRAIDCopyCommand (PrivateMethods)
-(BOOL)verifyDiskInformation:(NSDictionary*)diskinfo withChecksum:(NSString*)checksum;
-(void)startGatherInformation;
-(void)completeGatherInformation:(NSNotification*)ntf;
-(void)startAddTargetToRAIDSet;
-(void)completeAddTargetToRAIDSet:(NSNotification*)ntf;
-(void)startMonitorRebuildRAIDSet;
-(void)completeMonitorRebuildRAIDSet:(NSNotification*)ntf;
-(void)startRemoveTargetFromRAIDSet;
-(void)completeRemoveTargetFromRAIDSet:(NSNotification*)ntf;
@end


@implementation LCSRotavaultAppleRAIDCopyCommand
+(LCSRotavaultAppleRAIDCopyCommand*)commandWithSourceDevice:(NSString*)sourcedev
                                             sourceChecksum:(NSString*)sourcecheck
                                               targetDevice:(NSString*)targetdev
                                             targetChecksum:(NSString*)targetcheck
{
    return [[[LCSRotavaultAppleRAIDCopyCommand alloc] initWithSourceDevice:sourcedev
                                                            sourceChecksum:sourcecheck
                                                              targetDevice:targetdev
                                                            targetChecksum:targetcheck] autorelease];
}

-(id)initWithSourceDevice:(NSString*)sourcedev
           sourceChecksum:(NSString*)sourcecheck
             targetDevice:(NSString*)targetdev
           targetChecksum:(NSString*)targetcheck
{
    LCSINIT_SUPER_OR_RETURN_NIL();
    
    sourceDevice = [sourcedev copy];
    LCSINIT_RELEASE_AND_RETURN_IF_NIL(sourceDevice);
    sourceChecksum = [sourcecheck copy];
    LCSINIT_RELEASE_AND_RETURN_IF_NIL(sourceChecksum);
    targetDevice = [targetdev copy];
    LCSINIT_RELEASE_AND_RETURN_IF_NIL(targetDevice);
    targetChecksum = [targetcheck copy];
    LCSINIT_RELEASE_AND_RETURN_IF_NIL(targetChecksum);
    
    return self;
}

-(void)dealloc
{
    [sourceDevice release];
    [sourceChecksum release];
    [targetDevice release];
    [targetChecksum release];
    [raidUUID release];
    [super dealloc];
}

-(BOOL)verifyDiskInformation:(NSDictionary*)diskinfo withChecksum:(NSString*)checksum
{
    NSArray* components = [checksum componentsSeparatedByString:@":"];
    
    if ([components count] != 2) {
        /* FIXME: Error Description */
        NSError *err = LCSERROR_METHOD(LCSRotavaultErrorDomain, LCSUnexpectedInputReceivedError);
        [self handleError:err];
        return NO;
    }
    
    NSString* algo = [components objectAtIndex:0];
    NSString* actual = [components objectAtIndex:1];
    NSString* expected;
    
    if ([algo isEqualToString:@"sha1"]) {
        expected = [[LCSPropertyListSHA1Hash sha1HashFromPropertyList:diskinfo] stringWithHexBytes];
    }
    else if ([algo isEqualToString:@"uuid"]) {
        expected = [diskinfo objectForKey:@"VolumeUUID"];
    }
    else {
        /* FIXME: Error Description */
        NSError *err = LCSERROR_METHOD(LCSRotavaultErrorDomain, LCSUnexpectedInputReceivedError);
        [self handleError:err];
        return NO;
    }
    
    if (![actual isEqualToString:expected]) {
        /* FIXME: Error Description */
        NSError *err = LCSERROR_METHOD(LCSRotavaultErrorDomain, LCSUnexpectedInputReceivedError);
        [self handleError:err];
        return NO;
    }
    
    return YES;
}

-(void)startGatherInformation
{
    NSParameterAssert([activeControllers.controllers count] == 0);
    
    controller.progressMessage = [NSString localizedStringWithFormat:@"Gathering information"];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(completeGatherInformation:)
                                                 name:[LCSCommandControllerCollection notificationNameAllControllersEnteredState:LCSCommandStateFinished]
                                               object:activeControllers];
    
    sourceInfoCtl = [LCSCommandController controllerWithCommand:[LCSDiskInfoCommand commandWithDevicePath:sourceDevice]];
    sourceInfoCtl.title = [NSString localizedStringWithFormat:@"Get information on source device"];
    [activeControllers addController:sourceInfoCtl];
    [sourceInfoCtl start];
    
    targetInfoCtl = [LCSCommandController controllerWithCommand:[LCSDiskInfoCommand commandWithDevicePath:targetDevice]];
    targetInfoCtl.title = [NSString localizedStringWithFormat:@"Get information on target device"];
    [activeControllers addController:targetInfoCtl];
    [targetInfoCtl start];
}

-(void)completeGatherInformation:(NSNotification*)ntf
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:[LCSCommandControllerCollection notificationNameAllControllersEnteredState:LCSCommandStateFinished]
                                                  object:activeControllers];
    
    if (![self verifyDiskInformation:sourceInfoCtl.result withChecksum:sourceChecksum]) {
        return;
    }
    if (![self verifyDiskInformation:targetInfoCtl.result withChecksum:targetChecksum]) {
        return;
    }
    if (![[sourceInfoCtl.result objectForKey:@"RAIDSetStatus"] isEqualToString:@"Online"]) {
        NSError *error = LCSERROR_METHOD(LCSRotavaultErrorDomain, LCSParameterError,
                                         LCSERROR_LOCALIZED_DESCRIPTION(@"Source raid set is not online"));
        [self handleError:error];
        return;
    }
    if (![[sourceInfoCtl.result objectForKey:@"RAIDSetLevelType"] isEqualToString:@"Mirror"]) {
        NSError *error = LCSERROR_METHOD(LCSRotavaultErrorDomain, LCSParameterError,
                                         LCSERROR_LOCALIZED_DESCRIPTION(@"Source is not a mirror raid set"));
        [self handleError:error];
        return;
    }
    
    raidUUID = [[sourceInfoCtl.result objectForKey:@"RAIDSetUUID"] retain];
    if ([raidUUID length] != 36) {
        NSError *error = LCSERROR_METHOD(LCSRotavaultErrorDomain, LCSParameterError,
                                         LCSERROR_LOCALIZED_DESCRIPTION(@"UUID of raid set has wrong format"));
        [self handleError:error];
        return;
    }
    
    [self startAddTargetToRAIDSet];
}

-(void)startAddTargetToRAIDSet
{
    controller.progressMessage = [NSString localizedStringWithFormat:@"Adding target to RAID set"];
    
    LCSCommandController *ctl = [LCSCommandController controllerWithCommand:[LCSAppleRAIDAddMemberCommand
                                                                             commandWithRaidUUID:raidUUID
                                                                             devicePath:targetDevice]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(completeAddTargetToRAIDSet:)
                                                 name:[LCSCommandController notificationNameStateEntered:LCSCommandStateFinished]
                                               object:ctl];
    
    ctl.title = [NSString localizedStringWithFormat:@"Add target to RAID set"];
    [activeControllers addController:ctl];
    [ctl start];
}

-(void)completeAddTargetToRAIDSet:(NSNotification*)ntf
{
    LCSCommandController *ctl = [ntf object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:[LCSCommandController notificationNameStateEntered:LCSCommandStateFinished]
                                                  object:ctl];
    
    [self startMonitorRebuildRAIDSet];
}

-(void)startMonitorRebuildRAIDSet
{
    controller.progressMessage = [NSString localizedStringWithFormat:@"Performing block copy"];    
    LCSCommandController *ctl = [LCSCommandController controllerWithCommand:[LCSAppleRAIDMonitorRebuildCommand
                                                                             commandWithRaidUUID:raidUUID
                                                                             devicePath:targetDevice]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(completeMonitorRebuildRAIDSet:)
                                                 name:[LCSCommandController notificationNameStateEntered:LCSCommandStateFinished]
                                               object:ctl];
    
    ctl.title = [NSString localizedStringWithFormat:@"Block copy"];
    [activeControllers addController:ctl];
    [ctl start];
}

-(void)completeMonitorRebuildRAIDSet:(NSNotification*)ntf
{
    LCSCommandController *ctl = [ntf object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:[LCSCommandController notificationNameStateEntered:LCSCommandStateFinished]
                                                  object:ctl];
    [self startRemoveTargetFromRAIDSet];
}
                                 
-(void)startRemoveTargetFromRAIDSet
{
    controller.progressMessage = [NSString localizedStringWithFormat:@"Removing target from RAID set"];
    
    LCSCommandController *ctl = [LCSCommandController controllerWithCommand:[LCSAppleRAIDRemoveMemberCommand
                                                                             commandWithRaidUUID:raidUUID
                                                                             devicePath:targetDevice]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(completeRemoveTargetFromRAIDSet:)
                                                 name:[LCSCommandController notificationNameStateEntered:LCSCommandStateFinished]
                                               object:ctl];
    
    ctl.title = [NSString localizedStringWithFormat:@"Remove target from RAID set"];
    [activeControllers addController:ctl];
    [ctl start];    
}

-(void)completeRemoveTargetFromRAIDSet:(NSNotification*)ntf
{
    LCSCommandController *ctl = [ntf object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:[LCSCommandController notificationNameStateEntered:LCSCommandStateFinished]
                                                  object:ctl];
    
    controller.progressMessage = [NSString localizedStringWithFormat:@"Complete"];
    
    controller.state = LCSCommandStateFinished;
}    


-(void)start
{
    controller.state = LCSCommandStateRunning;
    [self startGatherInformation];
}

-(void)cancel
{
    [self handleError:LCSERROR_METHOD(NSCocoaErrorDomain, NSUserCancelledError)];    
}
@end
