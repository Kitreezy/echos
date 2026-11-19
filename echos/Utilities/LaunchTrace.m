//
//  LaunchTrace.m
//  echos
//
//  Разметка самого раннего куска запуска. Swift-код начинает выполняться уже
//  в main, поэтому +load здесь — единственная точка до него без лишней
//  связывающей обвязки. Интервал намеренно называется tail: полный pre-main
//  включает dyld и ObjC runtime, его честно меряет Instruments App Launch или
//  DYLD_PRINT_STATISTICS, а здесь отмечена часть от загрузки классов до
//  UIApplicationDidFinishLaunching.
//

@import UIKit;
@import OSLog;
#import <os/signpost.h>

@interface EchosLaunchTrace : NSObject
@end

@implementation EchosLaunchTrace

static os_log_t echosLaunchLog;
static os_signpost_id_t echosPreMainInterval;

+ (void)load {
    echosLaunchLog = os_log_create("com.kitreezy.echos", "launch");
    echosPreMainInterval = os_signpost_id_generate(echosLaunchLog);

    os_signpost_interval_begin(echosLaunchLog,
                               echosPreMainInterval,
                               "Pre-main tail");

    [NSNotificationCenter.defaultCenter
     addObserverForName:UIApplicationDidFinishLaunchingNotification
     object:nil
     queue:nil
     usingBlock:^(NSNotification *notification) {
        os_signpost_interval_end(echosLaunchLog,
                                 echosPreMainInterval,
                                 "Pre-main tail");
    }];
}

@end
