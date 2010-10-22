//
//  LCSRotavaultBlockCopyCommand.m
//  rotavault
//
//  Created by Lorenz Schori on 06.10.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import "LCSRotavaultBlockCopyCommand.h"
#import "LCSInitMacros.h"
#import "LCSCommandController.h"
#import "LCSDiskInfoCommand.h"
#import "LCSAsrRestoreCommand.h"
#import "LCSDiskMountCommand.h"
#import "LCSRotavaultError.h"
#import "LCSPropertyListSHA1Hash.h"
#import "NSData+Hex.h"

@interface LCSRotavaultBlockCopyCommand (PrivateMethods)
-(BOOL)verifyDiskInformation:(NSDictionary*)diskinfo withChecksum:(NSString*)checksum;
-(void)startGatherInformation;
-(void)completeGatherInformation:(NSNotification*)ntf;
-(void)startBlockCopy;
-(void)completeBlockCopy:(NSNotification*)ntf;
-(void)startSourceRemount;
-(void)completeSourceRemount:(NSNotification*)ntf;
@end


@implementation LCSRotavaultBlockCopyCommand
+(LCSRotavaultBlockCopyCommand*)commandWithSourceDevice:(NSString*)sourcedev
                                         sourceChecksum:(NSString*)sourcecheck
                                           targetDevice:(NSString*)targetdev
                                         targetChecksum:(NSString*)targetcheck
{
    return [[[LCSRotavaultBlockCopyCommand alloc] initWithSourceDevice:sourcedev
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
    [super dealloc];
}

-(void)handleError:(NSError*)err
{
    [super handleError:err];
    
    if (needsSourceRemount) {
        [self startSourceRemount];
    }
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
    
    self.progressMessage = [NSString localizedStringWithFormat:@"Gathering information"];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(completeGatherInformation:)
                                                 name:[LCSCommandControllerCollection notificationNameAllControllersEnteredState:LCSCommandStateFinished]
                                               object:activeControllers];
    
    sourceInfoCtl = [LCSDiskInfoCommand commandWithDevicePath:sourceDevice];
    sourceInfoCtl.title = [NSString localizedStringWithFormat:@"Get information on source device"];
    [activeControllers addController:sourceInfoCtl];
    [sourceInfoCtl start];
    
    targetInfoCtl = [LCSDiskInfoCommand commandWithDevicePath:targetDevice];
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
    
    [self startBlockCopy];
}

-(void)startBlockCopy
{
    self.progressMessage = [NSString localizedStringWithFormat:@"Performing block copy"];
    
    needsSourceRemount = YES;
    LCSCommandController *ctl = [LCSAsrRestoreCommand commandWithSource:sourceDevice target:targetDevice];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(completeBlockCopy:)
                                                 name:[LCSCommandController notificationNameStateEntered:LCSCommandStateFinished]
                                               object:ctl];
    ctl.title = [NSString localizedStringWithFormat:@"Block copy"];
    [activeControllers addController:ctl];
    
    self.progressIndeterminate = NO;
    [ctl addObserver:self forKeyPath:@"progress" options:0 context:nil];
    
    [ctl start];
}

-(void)observeValueForKeyPath:(NSString *)keyPath
                     ofObject:(id)object
                       change:(NSDictionary *)change
                      context:(void *)context
{
    if ([keyPath isEqualToString:@"progress"]) {
        self.progress = ((LCSCommandController*)object).progress;
    }
}

-(void)completeBlockCopy:(NSNotification*)ntf
{
    LCSCommandController* sender = [ntf object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:[LCSCommandController notificationNameStateEntered:sender.state]
                                                  object:sender];
    [sender removeObserver:self forKeyPath:@"progress"];
    self.progressIndeterminate = YES;
    
    needsSourceRemount = NO;
    
    self.progressMessage = [NSString localizedStringWithFormat:@"Complete"];
    
    self.state = LCSCommandStateFinished;
}

-(void)startSourceRemount
{
    self.progressMessage = [NSString localizedStringWithFormat:@"Remounting source device"];
    
    LCSCommandController *ctl = [LCSDiskMountCommand commandWithDevicePath:sourceDevice];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(completeSourceRemount:)
                                                 name:[LCSCommandController notificationNameStateEntered:LCSCommandStateInvalidated]
                                               object:ctl];
    ctl.title = [NSString localizedStringWithFormat:@"Remount source device"];
    [activeControllers addController:ctl];
    [ctl start];
}

-(void)completeSourceRemount:(NSNotification*)ntf
{
    LCSCommandController* sender = [ntf object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:[LCSCommandController notificationNameStateEntered:sender.state]
                                                  object:sender];
}

-(void)performStart
{
    self.state = LCSCommandStateRunning;
    [self startGatherInformation];
}

-(void)performCancel
{
    [self handleError:LCSERROR_METHOD(NSCocoaErrorDomain, NSUserCancelledError)];    
}
@end
