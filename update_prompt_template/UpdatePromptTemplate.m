/*
 * UpdatePromptTemplate.m —— 离线弹窗模板 dylib
 *
 * 用途：这是"弹窗生成器"的模板。所有配置以"等宽占位符"写死在二进制里，
 * iPhone 端的生成器 App 读取本模板 → 按固定偏移做等宽字符串替换 → 生成新 dylib。
 *
 * 不依赖服务器、不依赖 CydiaSubstrate，只依赖 UIKit/Foundation。
 *
 * ── 占位符布局（宽度即数组大小，生成器按固定长度替换，勿改）──
 *   kTitle[64]      标题        锚点 TITLE_BEGIN_
 *   kMessage[192]   内容        锚点 MESSAGE_BEGIN_
 *   kConfirm[32]    确认按钮    锚点 CONFIRM_BEGIN_
 *   kCancel[32]     取消按钮    锚点 CANCEL_BEGIN_
 *   kUrl[256]       跳转地址    锚点 URL_BEGIN_
 *   kPluginVer[32]  目标插件版本 锚点 PLUGINVER_BEGIN_
 *   kFlagUncond[2]  '1'=无条件弹(忽略版本对比)
 *   kFlagIgnore[2]  '1'=显示"不再提示"按钮(点了写入版本,不再提醒)
 *
 * ── 更新判断逻辑（以你的插件版本为准）──
 *   本地记录版本(微信沙盒 Documents/xh/plugin_ver.txt) < 内置目标插件版本 → 弹窗
 *   无目标版本 或 无条件弹 → 直接弹
 *   点"去更新" / "不再提示" → 把目标版本写入文件,停止提醒
 *   点"取消" → 不写文件,下次打开还弹
 */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

/* 等宽占位符(全局非 const,内容完整落在 __data 段,生成器可字节级定位替换) */
__attribute__((used)) static char kTitle[64]      = "TITLE_BEGIN_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
__attribute__((used)) static char kMessage[192]   = "MESSAGE_BEGIN_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
__attribute__((used)) static char kConfirm[32]    = "CONFIRM_BEGIN_CCCCCCCCCCCCCCCCC";
__attribute__((used)) static char kCancel[32]     = "CANCEL_BEGIN_DDDDDDDDDDDDDDDDDD";
__attribute__((used)) static char kUrl[256]       = "URL_BEGIN_EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE";
__attribute__((used)) static char kPluginVer[32]   = "PLUGINVER_BEGIN_FFFFFFFFFFFFFFF";
__attribute__((used)) static char kFlagUncond[2]  = "0";
__attribute__((used)) static char kFlagIgnore[2]  = "1";

/* 从占位符数组读取字符串(锚点之后到 null 截断) */
static NSString *strOf(char *buf, NSUInteger len) {
    if (!buf || buf[0] == 0) return @"";
    const char *end = memchr(buf, 0, len);
    size_t n = end ? (size_t)(end - buf) : len;
    NSString *s = [[NSString alloc] initWithBytes:buf length:n encoding:NSUTF8StringEncoding];
    return s.length ? s : @"";
}

/* 本地版本记录文件:微信沙盒 Documents/xh/plugin_ver.txt,目录不存在自动创建 */
static NSString *kVerFilePath(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/xh"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"plugin_ver.txt"];
}
static NSString *localPluginVersion(void) {
    NSString *v = [NSString stringWithContentsOfFile:kVerFilePath()
                                            encoding:NSUTF8StringEncoding error:nil];
    return v.length ? v : @"0.0.0";   // 没记录 = 旧版,弹
}
static void writePluginVersion(NSString *ver) {
    if (ver.length) [ver writeToFile:kVerFilePath() atomically:YES
                            encoding:NSUTF8StringEncoding error:nil];
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

static void showPopup(void) {
    NSString *title   = strOf(kTitle, sizeof kTitle);
    NSString *message = strOf(kMessage, sizeof kMessage);
    NSString *confirm = strOf(kConfirm, sizeof kConfirm);
    NSString *cancel  = strOf(kCancel, sizeof kCancel);
    NSString *url     = strOf(kUrl, sizeof kUrl);
    NSString *target  = strOf(kPluginVer, sizeof kPluginVer);
    BOOL hasIgnore    = kFlagIgnore[0] == '1';

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];

    /* 确认按钮:去更新 → 跳转 + 写入目标版本停止提醒 */
    [alert addAction:[UIAlertAction actionWithTitle:confirm
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        writePluginVersion(target);              // 视为已去更新,停止提醒
        if (url.length) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]
                                               options:@{} completionHandler:nil];
        }
    }]];

    if (hasIgnore) {
        /* 不再提示 → 写入目标版本,停止提醒 */
        [alert addAction:[UIAlertAction actionWithTitle:cancel
                                                  style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *a) {
            writePluginVersion(target);
        }]];
    } else if (cancel.length) {
        /* 纯取消 → 不写文件,下次继续弹 */
        [alert addAction:[UIAlertAction actionWithTitle:cancel
                                                  style:UIAlertActionStyleCancel handler:nil]];
    }

    UIViewController *top = topVC();
    if (top) dispatch_async(dispatch_get_main_queue(), ^{
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void checkForUpdate(void) {
    BOOL unconditional = kFlagUncond[0] == '1';
    NSString *target = strOf(kPluginVer, sizeof kPluginVer);

    BOOL outdated;
    if (unconditional || !target.length) {
        outdated = YES;                          // 无条件弹
    } else {
        NSString *cur = localPluginVersion();
        outdated = [cur compare:target options:NSNumericSearch] == NSOrderedAscending;
    }
    if (outdated) showPopup();
}

__attribute__((constructor))
static void entry(void) {
    double delay = 2.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ checkForUpdate(); });
}
