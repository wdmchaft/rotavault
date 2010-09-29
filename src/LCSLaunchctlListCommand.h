//
//  LCSLaunchctlListCommand.h
//  rotavault
//
//  Created by Lorenz Schori on 29.09.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LCSQuickExternalCommand.h"


@interface LCSLaunchctlListCommand : LCSQuickExternalCommand {
    NSMutableArray* joblist;
}
-(id)init;
+(LCSLaunchctlListCommand*)command;
@end
