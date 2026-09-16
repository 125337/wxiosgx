/*
 * UpdatePrompt.m —— 注入用弹窗插件
 * 行为完全由服务器控制:启动后请求 CONTROL_URL,按其返回的 JSON 决定是否弹窗。
 * 只依赖 Foundation/UIKit 系统库,不依赖 CydiaSubstrate,证书签后普通设备可跑。
 */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

/// TODO: 改成你自己的服务器地址(等用户提供后我替换)
static NSString *const kControlURL = @"https://gx.xhhan.xyz/popup.json";

/// 被推广插件的本地版本文件 —— 由"被推广插件"加载时写入自己的版本号,
/// 弹窗 dylib 读它跟服务器目标版本对比,判断该不该提示更新(与微信版本无关)
static NSString *kVerFilePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/plugin_ver.txt"];
}
static NSString *localPluginVersion(void) {
    NSString *v = [NSString stringWithContentsOfFile:kVerFilePath()
                                            encoding:NSUTF8StringEncoding error:nil];
    return v.length ? v : @"0.0.0";   // 没写过/未装被推广插件 = 视为旧版,弹
}

static NSString *keyFor(NSString *suffix, NSString *version) {
    return [NSString stringWithFormat:@"gd_popup_%@_%@",
            suffix,
            [[NSBundle mainBundle].bundleIdentifier stringByReplacingOccurrencesOfString:@"." withString:@"_"] ?: @"app"];
}

static UIViewController *topVC(void) {
    UIWindow *w = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (s.activationState == UISceneActivationStateForegroundActive) {
                w = s.keyWindow ?: s.windows.firstObject;
                if (w) break;
            }
        }
    }
    if (!w) w = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void showPopup(NSDictionary *cfg) {
    NSString *title   = cfg[@"title"]   ?: @"提示";
    NSString *message = cfg[@"message"] ?: @"";
    NSString *confirm = cfg[@"confirm"] ?: @"确定";
    NSString *cancel  = cfg[@"cancel"]  ?: @"取消";
    NSString *url     = cfg[@"url"];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    if (url.length) {
        [alert addAction:[UIAlertAction actionWithTitle:confirm
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]
                                               options:@{} completionHandler:nil];
        }]];
    }
    BOOL hasIgnore = [cfg[@"ignore_option"] boolValue];
    if (hasIgnore) {
        NSString *target = cfg[@"target_version"] ?: @"1.0.0";
        [alert addAction:[UIAlertAction actionWithTitle:cancel
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *a) {
            [[NSUserDefaults standardUserDefaults] setObject:target forKey:keyFor(@"ignored", target)];
        }]];
    } else if (cancel.length) {
        [alert addAction:[UIAlertAction actionWithTitle:cancel
                                                  style:UIAlertActionStyleCancel handler:nil]];
    }
    UIViewController *top = topVC();
    if (top) { dispatch_async(dispatch_get_main_queue(), ^{ [top presentViewController:alert animated:YES completion:nil]; }); }
}

static void handleConfig(NSDictionary *cfg) {
    if (![cfg isKindOfClass:NSDictionary.class]) return;
    if (![cfg[@"enabled"] boolValue]) return;                              // 服务器总开关

    // 更新判断:读"被推广插件"写在微信沙盒 Documents/plugin_ver.txt 的版本,
    // 低于服务器目标版本才弹(与微信版本、与弹窗 dylib 自身版本均无关)
    NSString *target = cfg[@"plugin_target_version"];
    NSString *curVer = localPluginVersion();                                // 无文件 = "0.0.0" = 视为旧版
    BOOL outdated;
    if (target.length) {
        outdated = [curVer compare:target options:NSNumericSearch] == NSOrderedAscending;
    } else {
        outdated = YES;                                                     // 服务器不设目标版本 = 无条件弹
    }

    // 调试模式:先弹调试框,显示拿到的配置/本地版本/判定,便于排查"没反应"
    if ([cfg[@"debug"] boolValue]) {
        NSString *info = [NSString stringWithFormat:
            @"已收到服务器配置 ✓\n本地插件版本(读 plugin_ver.txt): %@\n服务器目标版本: %@\n判定: %@\n\n配置原文:\n%@",
            curVer, target ?: @"-", outdated ? @"将继续弹窗" : @"已是最新,不弹", cfg];
        UIAlertController *dbg = [UIAlertController alertControllerWithTitle:@"[调试] 弹窗配置"
            message:info preferredStyle:UIAlertControllerStyleAlert];
        [dbg addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *top = topVC();
        if (top) dispatch_async(dispatch_get_main_queue(), ^{ [top presentViewController:dbg animated:YES completion:nil]; });
        return;                                                            // 调试时只看结果,不再弹正式框
    }
    if (!outdated) return;

    if ([cfg[@"once"] boolValue]) {                                        // 每版本只弹一次(含忽略)
        NSString *seenKey = keyFor(@"seen", target ?: @"any");
        if ([[NSUserDefaults standardUserDefaults] objectForKey:seenKey]) return;
        [[NSUserDefaults standardUserDefaults] setObject:@(YES) forKey:seenKey];
        NSString *ignKey = keyFor(@"ignored", target ?: @"any");
        if ([[NSUserDefaults standardUserDefaults] objectForKey:ignKey]) return;
    }
    showPopup(cfg);
}

static void checkForUpdate(void) {
    NSURL *u = [NSURL URLWithString:kControlURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.timeoutInterval = 8;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e || d.length == 0) return;                                    // 服务器挂/无网 = 不弹,不影响 App
        NSError *err = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
        if (err || !obj) return;
        handleConfig(obj);
    }] resume];
}

__attribute__((constructor))
static void entry(void) {
    // constructor 在进程启动早期执行,界面还没起来,延迟到启动后几秒再请求/弹窗
    double delay = 2.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ checkForUpdate(); });
}