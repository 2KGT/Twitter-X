//
//  Settings.x
//  NeoFreeBird
//

#import "Headers/XHeaders.h"
#import "HookHelpers.h"

// MARK: - NeoFreeBird settings entry

static const void* SettingsEntryKey = &SettingsEntryKey;
static const void* SettingsRootKey = &SettingsRootKey;

static BOOL isSettingsClass(UIViewController* viewController) {
    return [viewController isKindOfClass:objc_getClass("T1GenericSettingsViewController")] ||
           [viewController isKindOfClass:objc_getClass("T1SettingsViewController")];
}

// The generic controller backs the root and every sub-page alike, so the root is
// the first settings-class controller in the navigation stack.
static BOOL settingsVCIsRoot(TFNItemsDataViewController* settingsVC) {
    for (UIViewController* viewController in settingsVC.navigationController.viewControllers) {
        if (viewController == settingsVC) {
            return YES;
        }

        if (isSettingsClass(viewController)) {
            return NO;
        }
    }

    return NO;
}

static BOOL sectionsContainNeoFreeBirdEntry(NSArray* sections) {
    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            continue;
        }

        for (id entry in (NSArray*)section) {
            if (objc_getAssociatedObject(entry, SettingsEntryKey)) {
                return YES;
            }
        }
    }

    return NO;
}

static TFNSettingsNavigationItem* makeNeoFreeBirdSettingsItem(
    TFNItemsDataViewController* settingsVC) {
    UIColor* iconColor;
    if (@available(iOS 12.0, *)) {
        if (settingsVC.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            iconColor = [UIColor systemGray2Color];
        } else {
            iconColor = [UIColor secondaryLabelColor];
        }
    } else {
        iconColor = [UIColor secondaryLabelColor];
    }

    UIImage* twitterIcon = [UIImage tfn_vectorImageNamed:@"twitter"
                                                fitsSize:CGSizeMake(20, 20)
                                               fillColor:iconColor];

    TFNTwitterAccount* account = [(T1GenericSettingsViewController*)settingsVC account];
    TFNSettingsNavigationItem* bhtwitter = [[objc_getClass("TFNSettingsNavigationItem") alloc]
            initWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"]
                   detail:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"]
                 iconName:nil
        controllerFactory:^UIViewController* {
            return [BHTManager BHTSettingsWithAccount:account];
        }];

    if (twitterIcon) {
        [bhtwitter setValue:twitterIcon forKey:@"icon"];
    }

    objc_setAssociatedObject(bhtwitter, SettingsEntryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    return bhtwitter;
}

static NSArray* sectionsByInsertingEntry(TFNItemsDataViewController* settingsVC,
                                         NSArray* sections) {
    NSMutableArray* newSections = [sections mutableCopy] ?: [NSMutableArray array];
    [newSections insertObject:@[makeNeoFreeBirdSettingsItem(settingsVC)] atIndex:0];
    return newSections;
}

// Async settings fetches rebuild the sections and discard one-shot inserts, and
// root-ness is unknowable during the first build (not yet on the nav stack). So
// tag the root in viewWillAppear, insert once to repair the first build, and let
// the rebuild transform below re-add the entry on every later snapshot.
static void insertNeoFreeBirdSettingsIfRoot(TFNItemsDataViewController* settingsVC) {
    if (!settingsVCIsRoot(settingsVC)) {
        return;
    }

    objc_setAssociatedObject(settingsVC, SettingsRootKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (sectionsContainNeoFreeBirdEntry(settingsVC.sections)) {
        return;
    }

    settingsVC.sections = sectionsByInsertingEntry(settingsVC, settingsVC.sections);
}

static NSArray* sectionsWithNeoFreeBirdEntry(TFNItemsDataViewController* settingsVC,
                                             NSArray* sections) {
    if (!isSettingsClass(settingsVC)) {
        return sections;
    }

    if (![objc_getAssociatedObject(settingsVC, SettingsRootKey) boolValue]) {
        return sections;
    }

    if (sectionsContainNeoFreeBirdEntry(sections)) {
        return sections;
    }

    return sectionsByInsertingEntry(settingsVC, sections);
}

%hook T1GenericSettingsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    insertNeoFreeBirdSettingsIfRoot(self);
}
%end

%hook T1SettingsViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    insertNeoFreeBirdSettingsIfRoot(self);
}
%end

// Every sections rebuild runs through this transform right before setSections:,
// so hooking it on the base class covers both settings roots.
%hook TFNItemsDataViewController
- (NSArray*)updatedSections:(NSArray*)sections forStyle:(NSInteger)style {
    NSArray* updatedSections = %orig;
    return sectionsWithNeoFreeBirdEntry(self, updatedSections);
}
%end

// MARK: - NeoFreeBird settings gesture

@interface NFBSettingsGesture : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController* home;
@end

@implementation NFBSettingsGesture

- (BOOL)homeIsVisible {
    UIViewController* home = self.home;
    UINavigationController* nav = home.navigationController;
    if (!home.viewIfLoaded.window || !nav) {
        return NO;
    }

    UIViewController* top = nav.topViewController;
    for (UIViewController* vc = home; vc; vc = vc.parentViewController) {
        if (vc == top) {
            return YES;
        }
    }

    return NO;
}

- (void)handleLongPress:(UILongPressGestureRecognizer*)press {
    if (press.state != UIGestureRecognizerStateBegan || ![self homeIsVisible]) {
        return;
    }

    UIImpactFeedbackGenerator* haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    id account = nil;
    Class hostClass = objc_getClass("T1HostViewController");
    if ([hostClass respondsToSelector:@selector(sharedHostViewController)]) {
        id host = [hostClass sharedHostViewController];
        if ([host respondsToSelector:@selector(currentAccount)]) {
            account = [host currentAccount];
        }
    }

    [self.home.navigationController pushViewController:[BHTManager BHTSettingsWithAccount:account]
                                              animated:YES];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
    return [self homeIsVisible];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)other {
    return YES;
}

@end

static const void* SettingsGestureKey = &SettingsGestureKey;

// Code lifted from nyaathea's Twitter tweak (now abandoned)
void attachNeoFreeBirdSettingsGesture(UIViewController* home) {
    UINavigationBar* bar = home.navigationController.navigationBar;
    if (!bar) {
        return;
    }

    NFBSettingsGesture* target = objc_getAssociatedObject(bar, SettingsGestureKey);
    if (target) {
        target.home = home;
        return;
    }

    target = [NFBSettingsGesture new];
    target.home = home;

    UILongPressGestureRecognizer* press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:target
                                                      action:@selector(handleLongPress:)];
    press.cancelsTouchesInView = NO;
    press.delegate = target;
    [bar addGestureRecognizer:press];

    objc_setAssociatedObject(bar, SettingsGestureKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// MARK: - Change font

%hook UIFontPickerViewController
- (void)viewWillAppear:(BOOL)arg1 {
    %orig(arg1);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:[[BHTBundle sharedBundle]
                          localizedStringForKey:@"CUSTOM_FONTS_NAVIGATION_BUTTON_TITLE"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(customFontsHandler)];
}
%new
- (void)customFontsHandler {
    if ([[NSFileManager defaultManager]
            fileExistsAtPath:@"/var/mobile/Library/Fonts/AddedFontCache.plist"]) {
        NSAttributedString* AttString = [[NSAttributedString alloc]
            initWithString:[[BHTBundle sharedBundle] localizedStringForKey:@"CUSTOM_FONTS_MENU_TITLE"]
                attributes:@{
                    NSFontAttributeName: [BHTManager menuTitleFont],
                    NSForegroundColorAttributeName: UIColor.labelColor
                }];
        TFNActiveTextItem* title =
            [[%c(TFNActiveTextItem) alloc] initWithTextModel:[[%c(TFNAttributedTextModel) alloc]
                                                                     initWithAttributedString:AttString]
                                                    activeRanges:nil];

        NSMutableArray* actions = [[NSMutableArray alloc] init];
        [actions addObject:title];

        NSDictionary* plistDictionary = [NSPropertyListSerialization
            propertyListWithData:
                [NSData dataWithContentsOfURL:
                            [NSURL fileURLWithPath:@"/var/mobile/Library/Fonts/AddedFontCache.plist"]]
                         options:NSPropertyListImmutable
                          format:NULL
                           error:nil];
        [plistDictionary enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key, id _Nonnull obj,
                                                             BOOL* _Nonnull stop) {
            @try {
                NSString* fontName = ((NSArray*)[obj valueForKey:@"psNames"]).firstObject;
                TFNActionItem* fontAction = [%c(TFNActionItem)
                    actionItemWithTitle:fontName
                                 action:^{
                                     if (self.configuration.includeFaces) {
                                         [self setSelectedFontDescriptor:[UIFontDescriptor
                                                                             fontDescriptorWithFontAttributes:@{
                                                                                 UIFontDescriptorNameAttribute:
                                                                                     fontName
                                                                             }]];
                                     } else {
                                         [self setSelectedFontDescriptor:[UIFontDescriptor
                                                                             fontDescriptorWithFontAttributes:@{
                                                                                 UIFontDescriptorFamilyAttribute:
                                                                                     fontName
                                                                             }]];
                                     }
                                     [self.delegate fontPickerViewControllerDidPickFont:self];
                                 }];
                [actions addObject:fontAction];
            } @catch (NSException* exception) {
                NSLog(@"Unable to find installed fonts /n reason: %@", exception.reason);
            }
        }];

        TFNMenuSheetViewController* alert = [[%c(TFNMenuSheetViewController) alloc]
            initWithActionItems:[NSArray arrayWithArray:actions]];
        [alert tfnPresentedCustomPresentFromViewController:self animated:YES completion:nil];
    } else {
        UIAlertController* errAlert = [UIAlertController
            alertControllerWithTitle:@"BHTwitter"
                             message:[[BHTBundle sharedBundle]
                                         localizedStringForKey:@"CUSTOM_FONTS_TUT_ALERT_MESSAGE"]
                      preferredStyle:UIAlertControllerStyleAlert];

        [errAlert
            addAction:
                [UIAlertAction
                    actionWithTitle:[[BHTBundle sharedBundle]
                                        localizedStringForKey:@"INSTALL_IFONT_BUTTON_TITLE"]
                              style:UIAlertActionStyleDefault
                            handler:^(UIAlertAction* _Nonnull action) {
                                [[UIApplication sharedApplication]
                                              openURL:[NSURL
                                                          URLWithString:
                                                              @"https://apps.apple.com/sa/app/"
                                                              @"ifont-find-install-any-font/id1173222289"]
                                              options:@{}
                                    completionHandler:nil];
                            }]];
        [errAlert addAction:[UIAlertAction
                                actionWithTitle:[[BHTBundle sharedBundle]
                                                    localizedTwitterStringForKey:@"OK_ACTION_LABEL"]
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
        [self presentViewController:errAlert animated:true completion:nil];
    }
}
%end

// The picked font name for a weight, or nil when the user runs Twitter's own.
static NSString* CustomFontName(BOOL isBold) {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"custom_fonts"]) {
        return nil;
    }

    return [defaults objectForKey:isBold ? @"bhtwitter_font_2"
                                         : @"bhtwitter_font_1"];
}

%hook UIFont
+ (UIFont*)tfn_fontWithName:(NSString*)name size:(CGFloat)size {
    UIFont* origFont = %orig;

    BOOL isBold = [name containsString:@"Bold"] || [name containsString:@"Heavy"];
    NSString* customName = CustomFontName(isBold);
    if (!customName) {
        return origFont;
    }

    return [UIFont fontWithName:customName size:size] ?: origFont;
}
%end

%hook XFontCatalog

+ (UIFont*)tabularDigitsFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont* origFont = %orig;

    NSString* customName = CustomFontName(weight >= UIFontWeightSemibold);
    if (!customName) {
        return origFont;
    }

    UIFont* customFont = [UIFont fontWithName:customName size:size];
    if (!customFont) {
        return origFont;
    }

    // Keep the digits equal width so the timestamp doesn't shuffle its layout
    // on every tick; fonts without tabular figures just ignore the feature.
    return [customFont tfn_withMonospacedDigits] ?: customFont;
}

%end

%hook XDSButtonContentElement
+ (id)labelWithText:(id)text font:(id)font color:(id)color {
    id orig = %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"custom_fonts"]) {
        return orig;
    }

    BOOL isBold = [font containsString:@"Bold"] ||
                  [font containsString:@"Heavy"];

    NSString* customName = [[NSUserDefaults standardUserDefaults]
        objectForKey:isBold ? @"bhtwitter_font_2" : @"bhtwitter_font_1"];
    if (!customName) {
        return orig;
    }
    UIFont* customFont = [UIFont fontWithName:customName
                                         size:[(UIFont*)orig pointSize]];
    if (!customFont) {
        return orig;
    }

    return %orig(text, customFont, color);
}

%end

static UIFont* CustomFontReplacingFont(UIFont* originalFont, BOOL isBold) {
    NSString* customName = CustomFontName(isBold);
    if (!customName || !originalFont) {
        return originalFont;
    }

    return [UIFont fontWithName:customName size:originalFont.pointSize] ?: originalFont;
}

%hook XNAVNavigationController

- (void)viewDidLoad {
    %orig;

    NSString* customName = CustomFontName(YES);
    if (!customName) {
        return;
    }

    UINavigationBar* navigationBar = self.navigationBar;
    UINavigationBarAppearance* appearance =
        [navigationBar.standardAppearance copy];

    NSMutableDictionary* attributes =
        [appearance.titleTextAttributes mutableCopy] ?:
        [NSMutableDictionary dictionary];

    UIFont* originalFont = attributes[NSFontAttributeName];
    CGFloat size = originalFont ? originalFont.pointSize : 17.0;
    UIFont* customFont = [UIFont fontWithName:customName size:size];

    if (!customFont) {
        return;
    }

    attributes[NSFontAttributeName] = customFont;
    appearance.titleTextAttributes = attributes;
    navigationBar.standardAppearance = appearance;
}

%end
