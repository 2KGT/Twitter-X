//
//  ChatSettingsViewController.m
//  NeoFreeBird
//
//  Created by orionblur
//

#import "Settings/Pages/ChatSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"

@implementation ChatSettingsViewController

- (NSString*)pageKey {
    return @"chat";
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
}

@end
