import 'package:flutter/widgets.dart';

/// zh-CN / en-US strings. Labels that exist in ZCode reuse ZCode's wording
/// (`packages/ui/src/i18n/locales`).
class S {
  const S._(this.zh);
  final bool zh;

  static S of(BuildContext context) =>
      S._(Localizations.maybeLocaleOf(context)?.languageCode == 'zh');

  String _(String zhText, String enText) => zh ? zhText : enText;

  // App / devices
  String get appName => 'Zemote';
  String get devices => _('设备', 'Devices');
  String get addDevice => _('添加设备', 'Add device');
  String get editDevice => _('编辑设备', 'Edit device');
  String get deviceLink => _('ZCode Web 链接', 'ZCode Web link');
  String get deviceLinkHint => 'http://192.168.1.8:3030/?token=…';
  String get deviceLinkHelp => _(
      '在电脑上运行 zcode --web --host 0.0.0.0，把终端输出的 Network 链接粘贴到这里或扫码。',
      'Run `zcode --web --host 0.0.0.0` on your computer and paste the printed Network link, or scan it.');
  String get deviceName => _('名称（可选）', 'Name (optional)');
  String get scanQr => _('扫码', 'Scan QR');
  String get paste => _('粘贴', 'Paste');
  String get save => _('保存', 'Save');
  String get cancel => _('取消', 'Cancel');
  String get delete => _('删除', 'Delete');
  String get rename => _('重命名', 'Rename');
  String get retry => _('重试', 'Retry');
  String get reconnect => _('重新连接', 'Reconnect');
  String get updateLink => _('更新链接', 'Update link');
  String get removeDevice => _('移除设备', 'Remove device');
  String removeDeviceConfirm(String name) =>
      _('确定移除「$name」？', 'Remove "$name" from this app?');
  String get linkInvalid => _('无法识别的链接', 'Unrecognized link');
  String get linkLegacy => _('旧版中继链接（zcode.z.ai/remote）已不再支持，请使用 zcode --web 输出的链接。',
      'Legacy relay links are no longer supported; use the link printed by zcode --web.');
  String get noDevices => _('还没有设备', 'No devices yet');
  String get noDevicesHint => _('添加一台运行 ZCode Web 的电脑，即可在手机上继续任务。',
      'Link a computer running ZCode Web to continue your tasks from here.');
  String get online => _('已连接', 'Connected');
  String get connecting => _('连接中', 'Connecting');
  String get offline => _('已断开', 'Disconnected');
  String get unauthorized => _('令牌已失效', 'Token rejected');
  String get unauthorizedHint => _('每次启动 zcode --web 都会生成新的令牌，请更新链接。',
      'zcode --web prints a new token on every start. Update the link.');
  String retryingIn(int s) => _('$s 秒后重试', 'retrying in ${s}s');
  String get workspace => _('工作区', 'Workspace');
  String get switchDevice => _('切换设备', 'Switch device');

  // Sidebar
  String get newTask => _('新建任务', 'New task');
  String get search => _('搜索', 'Search');
  String get tasks => _('任务', 'Tasks');
  String get pinned => _('置顶', 'Pinned');
  String get archived => _('已归档', 'Archived');
  String get noTasks => _('还没有任务', 'No tasks yet');
  String get pin => _('置顶', 'Pin');
  String get unpin => _('取消置顶', 'Unpin');
  String get archive => _('归档', 'Archive');
  String get unarchive => _('取消归档', 'Unarchive');
  String get deleteTaskConfirm => _('删除后任务将从列表中移除。', 'The task will be removed from the list.');
  String get settings => _('设置', 'Settings');

  // Status
  String get statusRunning => _('执行中', 'Running');
  String get statusWaiting => _('等待确认', 'Awaiting approval');
  String get statusError => _('出错', 'Error');
  String get statusInterrupted => _('已中断', 'Interrupted');
  String get statusCompleted => _('已完成', 'Completed');

  // Conversation
  String greeting(int hour) {
    if (hour < 5) return _('夜深了！剩下的交给我。', 'Late night! Leave the rest to me.');
    if (hour < 12) return _('早上好！剩下的交给我。', 'Good morning! Leave the rest to me.');
    if (hour < 18) return _('下午好！剩下的交给我。', 'Good afternoon! Leave the rest to me.');
    return _('晚上好！剩下的交给我。', 'Good evening! Leave the rest to me.');
  }

  String get placeholderNewTask => _('向 ZCode 提问…', 'Ask ZCode anything…');
  String get placeholderFollowUp => _('提出后续修改要求', 'Ask for follow-up changes');
  String get placeholderQueue => _('继续输入以排队后续修改', 'Keep typing to queue follow-up changes');
  String get send => _('发送', 'Send');
  String get stop => _('停止生成', 'Stop');
  String get thinking => _('正在思考', 'Thinking');
  String get thought => _('思考', 'Thought');
  String workedFor(String d) => _('已工作 $d', 'Worked for $d');
  String get working => _('工作中', 'Working');
  String get loadOlder => _('加载更早的消息', 'Load earlier messages');
  String get loadingConversation => _('正在加载会话…', 'Loading conversation…');
  String get syncing => _('同步中…', 'Syncing…');
  String get copied => _('已复制', 'Copied');
  String get copy => _('复制', 'Copy');
  String get retryTurn => _('重试', 'Retry');
  String get edit => _('编辑', 'Edit');
  String get queued => _('排队中', 'Queued');
  String get sendNow => _('立即发送', 'Send now');
  String get queuePaused => _('队列已暂停', 'Queue paused');
  String get resume => _('继续', 'Resume');
  String get background => _('后台任务', 'Background');
  String get compact => _('压缩上下文', 'Compact');
  String get changes => _('变更', 'Changes');
  String get heldQueueTitle => _('队列已暂停', 'Queue is paused');
  String get heldQueueBody =>
      _('队列中还有待发送的消息。', 'There are queued messages waiting.');
  String get clearQueueAndSend => _('清空队列后发送', 'Clear queue and send');
  String get keepQueueAndSend => _('保留队列立即发送', 'Keep queue and send');
  String get offlineBanner => _('连接已断开，正在重连…', 'Disconnected, reconnecting…');
  String get noModels => _('当前设备没有可用的模型，请先在电脑上配置。',
      'No model configured on this device. Set one up on the computer first.');
  String get context => _('上下文', 'Context');

  // Tool status
  String get toolRunning => _('执行中', 'Running');
  String get toolDone => _('已执行', 'Done');
  String get toolFailed => _('执行失败', 'Failed');
  String get toolDenied => _('已拒绝', 'Denied');
  String get toolStopped => _('已停止', 'Stopped');
  String get toolPending => _('等待确认', 'Awaiting approval');
  String get input => _('输入', 'Input');
  String get output => _('输出', 'Output');

  // Modes (mode.label.glm.* in ZCode)
  String modeLabel(String mode) => switch (mode) {
        'build' => _('变更前确认', 'Ask before changes'),
        'edit' => _('自动编辑', 'Edit automatically'),
        'plan' => _('计划模式', 'Plan mode'),
        'yolo' => _('完全访问', 'Full access'),
        _ => mode,
      };
  String modeDescription(String mode) => switch (mode) {
        'build' => _('改文件前先问我。', 'Ask before file changes.'),
        'edit' => _('自动编辑文件。', 'Edit files automatically.'),
        'plan' => _('编辑前先出计划。', 'Plan before editing.'),
        'yolo' => _('减少确认次数。', 'Run with fewer confirmations.'),
        _ => '',
      };
  String get model => _('选择模型', 'Model');
  String get reasoning => _('思考档位', 'Reasoning');
  String reasoningLevel(String level) => switch (level) {
        'disabled' || 'none' => _('关', 'Off'),
        'enabled' => _('开', 'On'),
        'low' => _('低', 'Low'),
        'medium' => _('中', 'Medium'),
        'high' => _('高', 'High'),
        'max' || 'xhigh' => _('最高', 'Max'),
        _ => level,
      };

  // Interactions
  String get permissionTitle => _('需要权限', 'Permission required');
  String get allow => _('允许', 'Allow');
  String get deny => _('拒绝', 'Deny');
  String get feedbackPlaceholder => _('告诉模型接下来应该怎么做...', 'Tell the model what to do instead...');
  String get customAnswer => _('输入你的回答...', 'Type your answer...');
  String get submit => _('提交', 'Submit');
  String get next => _('下一题', 'Next');
  String get skip => _('跳过', 'Skip');
  String get decline => _('拒绝回答', 'Decline');
  String get questionTitle => _('需要你的回答', 'Input needed');

  // Settings
  String get appearance => _('外观', 'Appearance');
  String get theme => _('主题', 'Theme');
  String get themeSystem => _('跟随系统', 'System');
  String get themeLight => _('浅色', 'Light');
  String get themeDark => _('深色', 'Dark');
  String get textSize => _('字体大小', 'Text size');
  String get diagnostics => _('连接日志', 'Connection log');
  String get about => _('关于', 'About');
  String get aboutBody => _('Zemote 是 ZCode Web 的多设备移动客户端，直接通过 WebSocket RPC 连接每台电脑上的 zcode --web。',
      'Zemote is a multi-device mobile client for ZCode Web. It talks to each computer\'s zcode --web over WebSocket RPC.');
  String get clear => _('清空', 'Clear');
  String get error => _('出错了', 'Something went wrong');
}
