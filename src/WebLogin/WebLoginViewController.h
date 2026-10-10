//
//  WebLoginViewController.h
//  NeoFreeBird
//
//  Webview cookie login. X removed the legacy login endpoint.
//  To login now, we need to harvest an account's web cookies through a webview,
//  and then store those cookies as if they were an OAuth1 token. WebCreateTweet.x handles
//  resigning native requests with the harvested cookies, so the app doesn't throw a tantrum.
//

#import <UIKit/UIKit.h>

@interface WebLoginViewController : UIViewController
+ (void)presentLoginFrom:(UIViewController*)presenter;

+ (UINavigationController*)loginRootNavigationController;
@end
