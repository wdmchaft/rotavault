//
//  OCMock+NSTask.h
//  rotavault
//
//  Created by Lorenz Schori on 01.10.10.
//  Copyright 2010 znerol.ch. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OCMock/OCMock.h>


@interface OCMockObject (NSTask)
+(id)mockTask:(NSTask*)task withTerminationStatus:(int)terminationStatus stdoutData:(NSData*)stdoutData
   stderrData:(NSData*)stderrData;
@end
