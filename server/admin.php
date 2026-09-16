<?php
/* 弹窗配置后台 —— 单文件版,无需数据库
 * 放法与 popup.json 同一目录,浏览器访问 https://gx.xhhan.xyz/admin.php
 * 第一步: 把下面 $ADMIN_PASS 改成你自己的密码(改完再上传,或上传后用面板编辑器改)
 */
session_start();

$ADMIN_PASS = 'change-me-123';            // <<< 上传前改成你的密码
$DATA       = __DIR__ . '/popup.json';    // 与 dylib 读取的是同一个文件

$FIELDS = [
    'enabled'        => 'bool',
    'title'          => 'str',
    'message'        => 'str',
    'confirm'        => 'str',
    'cancel'         => 'str',
    'url'            => 'str',
    'plugin_target_version' => 'str',
    'debug'          => 'bool',
];
$DEFAULTS = [
    'enabled' => true, 'title' => '发现新版本', 'message' => '有新版本可用，是否前往更新？',
    'confirm' => '去更新', 'cancel' => '稍后', 'url' => '',
    'plugin_target_version' => '', 'debug' => false,
];

function load_cfg() {
    global $DATA, $DEFAULTS;
    $cfg = $DEFAULTS;
    if (file_exists($DATA)) {
        $j = json_decode(file_get_contents($DATA), true);
        if (is_array($j)) $cfg = array_merge($cfg, $j);
    }
    return $cfg;
}

/* 登录/登出/保存 */
$err = ''; $msg = '';
if (!empty($_SESSION['ok']) && isset($_GET['view']) && $_GET['view'] === 'json') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-cache, no-store');
    readfile($DATA);
    exit;
}
if (isset($_POST['logout'])) { session_destroy(); header('Location: admin.php'); exit; }
if (isset($_POST['pass'])) {
    if (hash_equals($ADMIN_PASS, (string)$_POST['pass'])) { $_SESSION['ok'] = 1; }
    else { $err = '密码错误'; }
}
if (!empty($_SESSION['ok']) && isset($_POST['save'])) {
    $cfg = [];
    foreach ($FIELDS as $k => $t) {
        if ($t === 'bool') $cfg[$k] = isset($_POST[$k]) && $_POST[$k] === '1';
        else               $cfg[$k] = trim((string)$_POST[$k]);
    }
    $json = json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if (file_put_contents($DATA, $json) !== false) { $_SESSION['flash_ok'] = '已保存，立即全局生效'; }
    else                                            $err = '写入失败，检查目录权限(需 web 用户可写)';
    if (!$err) { header('Location: admin.php'); exit; }
}

$cfg = load_cfg();
?>
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>弹窗配置后台</title>
<style>
body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;background:#f2f4f8;margin:0}
.card{max-width:560px;margin:40px auto;background:#fff;border-radius:12px;box-shadow:0 2px 12px rgba(0,0,0,.08);padding:28px 32px}
h1{font-size:20px;margin:0 0 20px}
label{display:block;font-size:13px;color:#555;margin:14px 0 6px}
input[type=text],input[type=password]{width:100%;box-sizing:border-box;padding:9px 11px;border:1px solid #d0d5dd;border-radius:8px;font-size:14px}
.row{display:flex;gap:16px}.row>div{flex:1}
.chk{display:flex;align-items:center;gap:8px;font-size:14px;color:#222;margin:10px 0}
.btn{display:inline-block;margin-top:18px;padding:10px 22px;border:0;border-radius:8px;font-size:15px;cursor:pointer;text-decoration:none}
.btn.primary{background:#2563eb;color:#fff}
.btn.secondary{background:#eef2f7;color:#444}
.note{font-size:12px;color:#888;margin-top:14px}
.ok{color:#16a34a;font-size:14px;margin-bottom:8px}
.err{color:#dc2626;font-size:14px;margin-bottom:8px}
.save-ok{background:#ecfdf5;border:1px solid #a7f3d0;color:#065f46;padding:8px 12px;border-radius:8px;margin-bottom:12px}
</style>
</head>
<body>
<div class="card">
<?php
if (!empty($_SESSION['flash_ok'])) {
    echo '<div class="save-ok">' . htmlspecialchars($_SESSION['flash_ok']) . '</div>';
    unset($_SESSION['flash_ok']);
}
?>
<?php if ($err) echo '<div class="err">' . htmlspecialchars($err) . '</div>'; ?>
<?php if (empty($_SESSION['ok'])): ?>
  <h1>弹窗配置后台 · 登录</h1>
  <form method="post">
    <label>密码</label>
    <input type="password" name="pass" required autofocus>
    <button class="btn primary" type="submit">登录</button>
    <p class="note">默认密码在 admin.php 第 8 行 $ADMIN_PASS，上传前先改掉。</p>
  </form>
<?php else: ?>
  <h1>弹窗配置后台</h1>
  <form method="post">
    <div class="row">
      <div class="chk"><input type="checkbox" name="enabled" value="1" <?php echo $cfg['enabled']?'checked':''; ?>> 启用弹窗(总开关)</div>
      <div class="chk"><input type="checkbox" name="debug" value="1" <?php echo $cfg['debug']?'checked':''; ?>> 调试模式</div>
    </div>
    <div class="row">
      <div><label>标题 title</label><input type="text" name="title" value="<?php echo htmlspecialchars($cfg['title']); ?>"></div>
      <div><label>确认按钮 confirm</label><input type="text" name="confirm" value="<?php echo htmlspecialchars($cfg['confirm']); ?>"></div>
    </div>
    <label>内容 message</label>
    <input type="text" name="message" value="<?php echo htmlspecialchars($cfg['message']); ?>">
    <div class="row">
      <div><label>取消按钮 cancel</label><input type="text" name="cancel" value="<?php echo htmlspecialchars($cfg['cancel']); ?>"></div>
      <div><label>下载地址 url(留空=不带跳转)</label><input type="text" name="url" value="<?php echo htmlspecialchars($cfg['url']); ?>"></div>
    </div>
    <div class="row">
      <div>
        <label>目标插件版本 plugin_target_version(留空=无条件弹)</label>
        <input type="text" name="plugin_target_version" value="<?php echo htmlspecialchars($cfg['plugin_target_version']); ?>">
        <div class="note">后台版本高于用户 dylib 内置版本 → 弹窗提示更新;等于内置版本 → 已最新,不弹。不写任何本地记录,没装上新版前每次启动都弹。</div>
      </div>
    </div>
    <button class="btn primary" type="submit" name="save" value="1">保存并生效</button>
    <a class="btn secondary" href="?view=json" target="_blank">查看 popup.json</a>
  </form>
  <form method="post" style="margin-top:10px"><button class="btn secondary" type="submit" name="logout" value="1">退出登录</button></form>
  <p class="note">修改后无需重启任何服务，保存即对全量用户生效。<br>调试模式开启后，用户打开 App 会先弹一个"调试框"显示「后台目标版本 vs dylib 内置版本」的判定结果与配置原文，用于排查。</p>
<?php endif; ?>
</div>
</body>
</html>