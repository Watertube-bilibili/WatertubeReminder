import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { promptAction } from '@kit.ArkUI';
import notificationManager from '@ohos.notificationManager';
import notification from '@ohos.notification';

const STORE_NAME = 'watertube_reminders';
const STORE_KEY = 'items';
const ALL_DAYS: Array<number> = [1, 2, 3, 4, 5, 6, 7];
const ALL_MONTHS: Array<number> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const WEEK_LABELS: Array<string> = ['一', '二', '三', '四', '五', '六', '日'];
const REMINDER_SLOT_TYPE: notification.SlotType = notification.SlotType.CONTENT_INFORMATION;

type RepeatMode = 'once' | 'daily' | 'weekly' | 'monthly' | 'yearly';

interface ReminderItem {
  id: string;
  title: string;
  note: string;
  hour: number;
  minute: number;
  enabled: boolean;
  reminderId: number;
  repeatMode: RepeatMode;
  year: number;
  month: number;
  day: number;
  daysOfWeek: Array<number>;
}

@Entry
@Component
struct Index {
  @State reminders: ReminderItem[] = [];
  @State showEditor: boolean = false;
  @State titleInput: string = '';
  @State noteInput: string = '';
  @State selectedTime: Date = new Date(2026, 0, 1, 9, 0, 0);
  @State selectedDate: Date = new Date();
  @State repeatMode: RepeatMode = 'daily';
  @State selectedWeekDays: Array<number> = [1, 2, 3, 4, 5];
  @State busy: boolean = false;

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.requestNoticePermission();
    this.loadReminders();
  }

  private async requestNoticePermission(): Promise<void> {
    try {
      await notificationManager.requestEnableNotification();
    } catch (err) {
      // The system may throw when notification is already enabled or managed in Settings.
    }
  }

  private async prepareReminderChannel(): Promise<void> {
    await this.requestNoticePermission();
    await reminderAgentManager.addNotificationSlot({
      type: REMINDER_SLOT_TYPE,
      level: notification.SlotLevel.LEVEL_HIGH,
      desc: '水管提醒通知',
      badgeFlag: true,
      vibrationEnabled: true
    });
  }

  private async loadReminders(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, STORE_NAME);
      const raw = await store.get(STORE_KEY, '[]');
      if (typeof raw === 'string') {
        const items = JSON.parse(raw) as ReminderItem[];
        this.reminders = items.map((item: ReminderItem): ReminderItem => this.normalizeItem(item));
      }
    } catch (err) {
      this.toast('读取提醒失败');
    }
  }

  private normalizeItem(item: ReminderItem): ReminderItem {
    const now = new Date();
    return {
      id: item.id,
      title: item.title,
      note: item.note ?? '',
      hour: item.hour,
      minute: item.minute,
      enabled: item.enabled,
      reminderId: item.reminderId ?? -1,
      repeatMode: item.repeatMode ?? 'daily',
      year: item.year ?? now.getFullYear(),
      month: item.month ?? (now.getMonth() + 1),
      day: item.day ?? now.getDate(),
      daysOfWeek: item.daysOfWeek?.length ? item.daysOfWeek : ALL_DAYS
    };
  }

  private async saveReminders(items: ReminderItem[]): Promise<void> {
    const store = await preferences.getPreferences(this.context, STORE_NAME);
    await store.put(STORE_KEY, JSON.stringify(items));
    await store.flush();
    this.reminders = items;
  }

  private isReminderLimitError(err: Object): boolean {
    const error = err as Record<string, Object>;
    return error['code'] === 1700002;
  }

  private async rebuildSystemReminders(items: Array<ReminderItem>): Promise<Array<ReminderItem>> {
    await this.prepareReminderChannel();
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (err) {
      // If there are no reminders to cancel, continue with a clean publish pass.
    }

    const rebuilt: Array<ReminderItem> = [];
    for (let index = 0; index < items.length; index++) {
      const item = items[index];
      let reminderId = -1;
      if (item.enabled) {
        reminderId = await this.publishReminder(item);
      }
      rebuilt.push({
        id: item.id,
        title: item.title,
        note: item.note,
        hour: item.hour,
        minute: item.minute,
        enabled: item.enabled,
        reminderId,
        repeatMode: item.repeatMode,
        year: item.year,
        month: item.month,
        day: item.day,
        daysOfWeek: item.daysOfWeek
      });
    }
    return rebuilt;
  }

  private resetEditor(): void {
    const now = new Date();
    this.titleInput = '';
    this.noteInput = '';
    this.selectedTime = new Date(2026, 0, 1, 9, 0, 0);
    this.selectedDate = now;
    this.repeatMode = 'daily';
    this.selectedWeekDays = [1, 2, 3, 4, 5];
  }

  private openEditor(): void {
    this.resetEditor();
    this.showEditor = true;
  }

  private closeEditor(): void {
    this.showEditor = false;
  }

  private async addReminder(): Promise<void> {
    const title = this.titleInput.trim();
    if (!title) {
      this.toast('先写提醒内容');
      return;
    }
    if (this.repeatMode === 'weekly' && this.selectedWeekDays.length === 0) {
      this.toast('至少选择一天');
      return;
    }

    this.busy = true;
    const item: ReminderItem = {
      id: Date.now().toString(),
      title,
      note: this.noteInput.trim(),
      hour: this.selectedTime.getHours(),
      minute: this.selectedTime.getMinutes(),
      enabled: true,
      reminderId: -1,
      repeatMode: this.repeatMode,
      year: this.selectedDate.getFullYear(),
      month: this.selectedDate.getMonth() + 1,
      day: this.selectedDate.getDate(),
      daysOfWeek: this.selectedWeekDays.concat([]).sort()
    };

    try {
      await this.prepareReminderChannel();
      try {
        item.reminderId = await this.publishReminder(item);
        await this.saveReminders([item].concat(this.reminders));
      } catch (err) {
        if (!this.isReminderLimitError(err)) {
          this.toast("创建失败：" + this.errorText(err));
          this.busy = false;
          return;
        }
        const rebuilt = await this.rebuildSystemReminders([item].concat(this.reminders));
        await this.saveReminders(rebuilt);
      }
      this.showEditor = false;
      this.toast('已添加');
    } catch (err) {
      this.toast("创建失败：" + this.errorText(err));
    }
    this.busy = false;
  }

  private async publishReminder(item: ReminderItem): Promise<number> {
    if (item.repeatMode === 'daily' || item.repeatMode === 'weekly') {
      const request: reminderAgentManager.ReminderRequestAlarm = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
        hour: item.hour,
        minute: item.minute,
        daysOfWeek: item.repeatMode === 'daily' ? ALL_DAYS : item.daysOfWeek,
        title: '水管提醒',
        content: this.notificationContent(item),
        expiredContent: item.title,
        snoozeContent: item.title,
        notificationId: Number(item.id.slice(-8)),
        slotType: REMINDER_SLOT_TYPE,
        tapDismissed: true,
        wantAgent: {
          pkgName: 'com.watertube.watertubereminder',
          abilityName: 'EntryAbility'
        }
      };
      return await reminderAgentManager.publishReminder(request);
    }

    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: item.year,
        month: item.month,
        day: item.day,
        hour: item.hour,
        minute: item.minute,
        second: 0
      },
      title: '水管提醒',
      content: this.notificationContent(item),
      expiredContent: item.title,
      snoozeContent: item.title,
      notificationId: Number(item.id.slice(-8)),
      slotType: REMINDER_SLOT_TYPE,
      tapDismissed: true,
      wantAgent: {
        pkgName: 'com.watertube.watertubereminder',
        abilityName: 'EntryAbility'
      }
    };

    if (item.repeatMode === 'monthly') {
      request.repeatMonths = ALL_MONTHS;
      request.repeatDays = [item.day];
    } else if (item.repeatMode === 'yearly') {
      request.repeatMonths = [item.month];
      request.repeatDays = [item.day];
    }

    return await reminderAgentManager.publishReminder(request);
  }

  private notificationContent(item: ReminderItem): string {
    return item.note ? `${item.title}：${item.note}` : item.title;
  }

  private async setReminderEnabled(item: ReminderItem, enabled: boolean): Promise<void> {
    this.busy = true;
    try {
      let reminderId = item.reminderId;
      if (enabled) {
        await this.prepareReminderChannel();
        reminderId = await this.publishReminder(item);
      } else if (reminderId >= 0) {
        await reminderAgentManager.cancelReminder(reminderId);
        reminderId = -1;
      }

      await this.saveReminders(this.reminders.map((current: ReminderItem): ReminderItem => {
        if (current.id === item.id) {
                    return {
            id: current.id,
            title: current.title,
            note: current.note,
            hour: current.hour,
            minute: current.minute,
            enabled,
            reminderId,
            repeatMode: current.repeatMode,
            year: current.year,
            month: current.month,
            day: current.day,
            daysOfWeek: current.daysOfWeek
          };
        }
        return current;
      }));
    } catch (err) {
      this.toast('操作失败');
    }
    this.busy = false;
  }

  private async deleteReminder(item: ReminderItem): Promise<void> {
    this.busy = true;
    try {
      if (item.reminderId >= 0) {
        await reminderAgentManager.cancelReminder(item.reminderId);
      }
      await this.saveReminders(this.reminders.filter((current: ReminderItem): boolean => current.id !== item.id));
      this.toast('已删除');
    } catch (err) {
      this.toast('删除失败');
    }
    this.busy = false;
  }

  private toggleWeekDay(day: number): void {
    if (this.selectedWeekDays.includes(day)) {
      this.selectedWeekDays = this.selectedWeekDays.filter((item: number): boolean => item !== day);
    } else {
      this.selectedWeekDays = this.selectedWeekDays.concat([day]).sort();
    }
  }

  private formatTime(hour: number, minute: number): string {
    const h = hour < 10 ? `0${hour}` : `${hour}`;
    const m = minute < 10 ? `0${minute}` : `${minute}`;
    return `${h}:${m}`;
  }

  private repeatText(item: ReminderItem): string {
    if (item.repeatMode === 'once') {
      return `${item.year}-${this.two(item.month)}-${this.two(item.day)} ${this.formatTime(item.hour, item.minute)}`;
    }
    if (item.repeatMode === 'daily') {
      return `每天 ${this.formatTime(item.hour, item.minute)}`;
    }
    if (item.repeatMode === 'weekly') {
      return `每周${this.weekText(item.daysOfWeek)} ${this.formatTime(item.hour, item.minute)}`;
    }
    if (item.repeatMode === 'monthly') {
      return `每月${item.day}日 ${this.formatTime(item.hour, item.minute)}`;
    }
    return `每年${item.month}月${item.day}日 ${this.formatTime(item.hour, item.minute)}`;
  }

  private weekText(days: Array<number>): string {
    return days.map((day: number): string => WEEK_LABELS[day - 1]).join('、');
  }

  private two(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private errorText(err: Object): string {
    const error = err as Record<string, Object>;
    if (error['code'] === 1700001) {
      return '系统通知仍未对水管提醒生效，请在系统设置里确认“水管提醒”的通知和提醒权限都已允许';
    }
    if (error['code'] === 1700002) {
      return '系统提醒数量已满，已尝试清理本应用旧提醒；请再点一次保存';
    }
    const code = error['code'];
    const message = error['message'];
    if (code !== undefined && message !== undefined) {
      return `${code} ${message}`;
    }
    if (code !== undefined) {
      return `${code}`;
    }
    if (message !== undefined) {
      return `${message}`;
    }
    return '未知错误';
  }

  private toast(message: string): void {
    promptAction.showToast({ message, duration: 2200 });
  }

  @Builder
  private ReminderRow(item: ReminderItem) {
    Row() {
      Column() {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#111111')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.repeatText(item))
          .fontSize(13)
          .fontColor('#666666')
          .margin({ top: 5 })

        if (item.note) {
          Text(item.note)
            .fontSize(13)
            .fontColor('#777777')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 5 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: item.enabled })
        .selectedColor('#1F8A70')
        .enabled(!this.busy)
        .onChange((isOn: boolean) => {
          this.setReminderEnabled(item, isOn);
        })

      Button('删除')
        .fontSize(13)
        .fontColor('#A33B32')
        .backgroundColor('#00000000')
        .enabled(!this.busy)
        .margin({ left: 4 })
        .onClick(() => {
          this.deleteReminder(item);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 10, top: 14, bottom: 14 })
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .margin({ bottom: 10 })
  }

  @Builder
  private RepeatButton(label: string, mode: RepeatMode) {
    Button(label)
      .height(34)
      .fontSize(13)
      .fontColor(this.repeatMode === mode ? '#FFFFFF' : '#333333')
      .backgroundColor(this.repeatMode === mode ? '#1F8A70' : '#EEF1EF')
      .borderRadius(17)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.repeatMode = mode;
      })
  }

  @Builder
  private WeekButton(day: number, label: string) {
    Button(label)
      .width(38)
      .height(34)
      .fontSize(13)
      .fontColor(this.selectedWeekDays.includes(day) ? '#FFFFFF' : '#333333')
      .backgroundColor(this.selectedWeekDays.includes(day) ? '#1F8A70' : '#EEF1EF')
      .borderRadius(17)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.toggleWeekDay(day);
      })
  }

  @Builder
  private ListPage() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Column() {
          Text('水管提醒')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111111')
            .width('100%')

          Text(`${this.reminders.length} 个提醒`)
            .fontSize(13)
            .fontColor('#666666')
            .margin({ top: 6 })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 12 })

        if (this.reminders.length === 0) {
          Column() {
            Text('暂无提醒')
              .fontSize(17)
              .fontColor('#333333')
            Text('点右下角加号添加')
              .fontSize(13)
              .fontColor('#777777')
              .margin({ top: 6 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        } else {
          List() {
            ForEach(this.reminders, (item: ReminderItem) => {
              ListItem() {
                this.ReminderRow(item)
              }
            }, (item: ReminderItem) => item.id)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 88 })
        }
      }
      .width('100%')
      .height('100%')

      Button('+')
        .width(56)
        .height(56)
        .fontSize(30)
        .fontColor('#FFFFFF')
        .backgroundColor('#1F8A70')
        .borderRadius(28)
        .margin({ right: 22, bottom: 24 })
        .enabled(!this.busy)
        .onClick(() => {
          this.openEditor();
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private EditorPage() {
    Column() {
      Row() {
        Button('返回')
          .height(36)
          .fontSize(14)
          .fontColor('#333333')
          .backgroundColor('#EEF1EF')
          .borderRadius(18)
          .onClick(() => {
            this.closeEditor();
          })

        Text('添加提醒')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111111')
          .margin({ left: 14 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 12 })

      Scroll() {
        Column() {
          TextInput({ placeholder: '提醒内容，例如：去某软件签到', text: this.titleInput })
            .height(46)
            .fontSize(15)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .onChange((value: string) => {
              this.titleInput = value;
            })

          TextInput({ placeholder: '备注，可不填', text: this.noteInput })
            .height(42)
            .fontSize(14)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .margin({ top: 8 })
            .onChange((value: string) => {
              this.noteInput = value;
            })

          Column() {
            Text('重复')
              .fontSize(15)
              .fontColor('#333333')
              .width('100%')
              .margin({ bottom: 10 })

            Flex({ wrap: FlexWrap.Wrap }) {
              this.RepeatButton('仅一次', 'once')
              this.RepeatButton('每天', 'daily')
              this.RepeatButton('每周', 'weekly')
              this.RepeatButton('每月', 'monthly')
              this.RepeatButton('每年', 'yearly')
            }
          }
          .width('100%')
          .padding(14)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .margin({ top: 10 })

          if (this.repeatMode === 'weekly') {
            Column() {
              Text('星期')
                .fontSize(15)
                .fontColor('#333333')
                .width('100%')
                .margin({ bottom: 10 })

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(ALL_DAYS, (day: number) => {
                  this.WeekButton(day, WEEK_LABELS[day - 1])
                })
              }
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .margin({ top: 10 })
          }

          if (this.repeatMode === 'once' || this.repeatMode === 'monthly' || this.repeatMode === 'yearly') {
            Row() {
              Text(this.repeatMode === 'monthly' ? '选择日期中的“日”' : '日期')
                .fontSize(15)
                .fontColor('#333333')
              Blank()
              DatePicker({ start: new Date(2020, 0, 1), end: new Date(2099, 11, 31), selected: this.selectedDate })
                .height(150)
                .onChange((value: DatePickerResult) => {
                  this.selectedDate = new Date(value.year ?? this.selectedDate.getFullYear(), (value.month ?? (this.selectedDate.getMonth() + 1)) - 1, value.day ?? this.selectedDate.getDate());
                })
            }
            .height(158)
            .padding({ left: 12, right: 12 })
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .margin({ top: 10 })
          }

          Row() {
            Text('时间')
              .fontSize(15)
              .fontColor('#333333')
            Blank()
            TimePicker({ selected: this.selectedTime })
              .useMilitaryTime(true)
              .height(130)
              .onChange((value: TimePickerResult) => {
                const next = new Date(this.selectedTime.getTime());
                next.setHours(value.hour ?? 9);
                next.setMinutes(value.minute ?? 0);
                this.selectedTime = next;
              })
          }
          .height(138)
          .padding({ left: 12, right: 12 })
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .margin({ top: 10 })

          Button(this.busy ? '处理中' : '保存提醒')
            .width('100%')
            .height(44)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor('#1F8A70')
            .borderRadius(8)
            .enabled(!this.busy)
            .margin({ top: 14, bottom: 24 })
            .onClick(() => {
              this.addReminder();
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.showEditor) {
        this.EditorPage()
      } else {
        this.ListPage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }
}

