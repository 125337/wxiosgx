/*
 * UpdatePromptTemplate.m —— 弹窗模板 dylib(在线版)
 *
 * 用途:这是"弹窗生成器"的模板。生成器 App 只往二进制里写入一个"版本标记"
 * (PLUGINVER_BEGIN_),其余一切(标题/文字/按钮/下载链接/目标版本)全部由
 * 服务器 popup.json 控制,改后台即可全局生效,无需重新生成。
 *
 * ── 占位符布局(宽度即数组大小,生成器按固定长度替换,勿改)──
 *   kPluginVer[32]  版本标记  锚点 PLUGINVER_BEGIN_ (留空=无条件弹)
 *
 * ── 更新判断逻辑(以后台版本为准)──
 *   后台 plugin_target_version >  dylib 内置版本标记 → 弹窗提示更新
 *   后台 plugin_target_version == 内置版本标记      → 已是最新,不弹
 *   后台未填目标版本                                → 无条件弹
 *   不写任何本地记录:没装上包含新版本 dylib 的 IPA 前,每次启动都弹。
 *
 * 不依赖 CydiaSubstrate,只依赖 UIKit/Foundation。
 */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

/* 服务器控制地址 */
static NSString *const kControlURL = @"https://gx.xhhan.xyz/popup.json";

/* 版本标记占位符(全局非 const,内容完整落在 __data 段,生成器可字节级定位替换) */
__attribute__((used)) static char kPluginVer[32] = "PLUGINVER_BEGIN_FFFFFFFFFFFFFFF";

/* 从占位符数组读取字符串:跳过定位锚点,读到 null 截断 */
static NSString *strOf(char *buf, NSUInteger len, const char *anchor) {
    if (!buf) return @"";
    size_t skip = strlen(anchor);
    if (skip >= len) return @"";
    char *s = buf + skip;
    if (s[0] == 0) return @"";
    const char *end = memchr(s, 0, len - skip);
    size_t n = end ? (size_t)(end - s) : (len - skip);
    NSString *str = [[NSString alloc] initWithBytes:s length:n encoding:NSUTF8StringEncoding];
    return str.length ? str : @"";
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

/* 弹窗:内容全部来自服务器配置,不写任何本地记录 */
static void showPopup(NSDictionary *cfg) {
    NSString *title   = cfg[@"title"]   ?: @"提示";
    NSString *message = cfg[@"message"] ?: @"";
    NSString *confirm = cfg[@"confirm"] ?: @"去更新";
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
    if (cancel.length) {
        [alert addAction:[UIAlertAction actionWithTitle:cancel
                                                  style:UIAlertActionStyleCancel handler:nil]];
    }
    UIViewController *top = topVC();
    if (top) dispatch_async(dispatch_get_main_queue(), ^{
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void handleConfig(NSDictionary *cfg) {
    if (![cfg isKindOfClass:NSDictionary.class]) return;
    BOOL enabled = YES;
    if (cfg[@"enabled"] != nil) enabled = [cfg[@"enabled"] boolValue];   // 字段缺失默认开启
    if (!enabled) return;                                                // 服务器总开关

    NSString *target = cfg[@"plugin_target_version"];                    // 后台目标版本
    NSString *local  = strOf(kPluginVer, sizeof kPluginVer, "PLUGINVER_BEGIN_");  // dylib 内置版本标记

    BOOL outdated;
    NSString *judge;
    if (!target.length) {
        outdated = YES;                                  // 后台没填目标版本 = 无条件弹
        judge = @"后台未填目标版本,无条件弹";
    } else {
        NSString *cur = local.length ? local : @"0.0.0"; // 内置版本缺失 = 视为旧版,弹
        outdated = [cur compare:target options:NSNumericSearch] == NSOrderedAscending;
        judge = [NSString stringWithFormat:@"后台目标 %@ vs dylib 内置 %@ %@",
                 target, cur, outdated ? @"→弹" : @"→不弹"];
    }

    // 调试模式:先弹调试框显示判定结果,便于排查"没反应"
    if ([cfg[@"debug"] boolValue]) {
        NSString *info = [NSString stringWithFormat:
            @"已收到服务器配置 ✓\n判断: %@\n\n配置原文:\n%@", judge, cfg];
        UIAlertController *dbg = [UIAlertController alertControllerWithTitle:@"[调试] 弹窗配置"
            message:info preferredStyle:UIAlertControllerStyleAlert];
        [dbg addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *top = topVC();
        if (top) dispatch_async(dispatch_get_main_queue(), ^{
            [top presentViewController:dbg animated:YES completion:nil];
        });
        return;                                                        // 调试时只看结果,不再弹正式框
    }
    if (!outdated) return;
    showPopup(cfg);
}

static void checkForUpdate(void) {
    NSURL *u = [NSURL URLWithString:kControlURL];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.timeoutInterval = 8;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e || d.length == 0) return;                                // 服务器挂/无网 = 不弹,不影响 App
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
