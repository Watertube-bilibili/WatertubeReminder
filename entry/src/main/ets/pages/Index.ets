import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { promptAction } from '@kit.ArkUI';

const STORE_NAME = 'watertube_reminders';
const STORE_KEY = 'items';
const ALL_DAYS: Array<number> = [1, 2, 3, 4, 5, 6, 7];

interface ReminderItem {
  id: string;
  title: string;
  note: string;
  hour: number;
  minute: number;
  enabled: boolean;
  reminderId: number;
}

@Entry
@Component
struct Index {
  @State reminders: ReminderItem[] = [];
  @State titleInput: string = '';
  @State noteInput: string = '';
  @State selectedTime: Date = new Date(2026, 0, 1, 9, 0, 0);
  @State busy: boolean = false;

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.loadReminders();
  }

  private async loadReminders(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, STORE_NAME);
      const raw = await store.get(STORE_KEY, '[]');
      if (typeof raw === 'string') {
        const items = JSON.parse(raw) as ReminderItem[];
        this.reminders = items.map((item: ReminderItem): ReminderItem => ({
          id: item.id,
          title: item.title,
          note: item.note,
          hour: item.hour,
          minute: item.minute,
          enabled: item.enabled,
          reminderId: item.reminderId ?? -1
        }));
      }
    } catch (err) {
      this.toast('读取提醒失败');
    }
  }

  private async saveReminders(items: ReminderItem[]): Promise<void> {
    const store = await preferences.getPreferences(this.context, STORE_NAME);
    await store.put(STORE_KEY, JSON.stringify(items));
    await store.flush();
    this.reminders = items;
  }

  private async addReminder(): Promise<void> {
    const title = this.titleInput.trim();
    if (!title) {
      this.toast('先写提醒内容');
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
      reminderId: -1
    };

    try {
      item.reminderId = await this.publishDailyReminder(item);
      await this.saveReminders([item, ...this.reminders]);
      this.titleInput = '';
      this.noteInput = '';
      this.toast('已添加');
    } catch (err) {
      this.toast('创建失败，请确认通知权限已开启');
    }
    this.busy = false;
  }

  private async publishDailyReminder(item: ReminderItem): Promise<number> {
    const request: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: item.hour,
      minute: item.minute,
      daysOfWeek: ALL_DAYS,
      title: '水管提醒',
      content: item.note ? `${item.title}：${item.note}` : item.title,
      expiredContent: item.title,
      snoozeContent: item.title,
      notificationId: Number(item.id.slice(-8)),
      slotType: 0,
      tapDismissed: true,
      wantAgent: {
        pkgName: 'com.watertube.watertubereminder',
        abilityName: 'EntryAbility'
      }
    };
    return await reminderAgentManager.publishReminder(request);
  }

  private async setReminderEnabled(item: ReminderItem, enabled: boolean): Promise<void> {
    this.busy = true;
    try {
      let reminderId = item.reminderId;
      if (enabled) {
        reminderId = await this.publishDailyReminder(item);
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
            reminderId
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

  private formatTime(hour: number, minute: number): string {
    const h = hour < 10 ? `0${hour}` : `${hour}`;
    const m = minute < 10 ? `0${minute}` : `${minute}`;
    return `${h}:${m}`;
  }

  private toast(message: string): void {
    promptAction.showToast({ message, duration: 1800 });
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

        Text(`${this.formatTime(item.hour, item.minute)}  每天`)
          .fontSize(13)
          .fontColor('#666666')
          .margin({ top: 4 })

        if (item.note) {
          Text(item.note)
            .fontSize(13)
            .fontColor('#777777')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
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

  build() {
    Column() {
      Column() {
        Text('水管提醒')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111111')
          .width('100%')

        Text('每天准时提醒签到、打卡和别忘的小事')
          .fontSize(13)
          .fontColor('#666666')
          .margin({ top: 6 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 10 })

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

        Row() {
          Text('时间')
            .fontSize(15)
            .fontColor('#333333')

          Blank()

          TimePicker({ selected: this.selectedTime })
            .useMilitaryTime(true)
            .height(120)
            .onChange((value: TimePickerResult) => {
              const next = new Date(this.selectedTime.getTime());
              next.setHours(value.hour ?? 9);
              next.setMinutes(value.minute ?? 0);
              this.selectedTime = next;
            })
        }
        .height(128)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .margin({ top: 8 })

        Button(this.busy ? '处理中' : '添加提醒')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#1F8A70')
          .borderRadius(8)
          .enabled(!this.busy)
          .margin({ top: 10 })
          .onClick(() => {
            this.addReminder();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 12 })

      if (this.reminders.length === 0) {
        Column() {
          Text('暂无提醒')
            .fontSize(16)
            .fontColor('#333333')
          Text('添加后会调用系统提醒，到点弹出通知')
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
        .padding({ left: 20, right: 20, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F7F6')
  }
}
