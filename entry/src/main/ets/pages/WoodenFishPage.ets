import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { vibrator } from '@kit.SensorServiceKit';

/**
 * 木鱼页面（黑白色主题）
 * - 顶部左侧：重置按钮；顶部中间：震动开关；顶部右侧：计数器（持久化保存）
 * - 屏幕中间：木鱼（Image，资源名 app.media.fish）
 * - 点击木鱼：按压反馈 + 木鱼上方「+1 功德」弹幕从右向左划过 + 计数 +1 + （可选）震动
 */

// 持久化存储键
const PREF_NAME = 'woodenfish_pref';
const KEY_COUNT = 'tap_count';
const KEY_VIBRATE = 'vibrate_enabled';

// 弹幕横向移动范围（从右侧屏幕外进入，移出左侧屏幕外）
const SCREEN_LEFT = -400;
const SCREEN_RIGHT = 400;
// 弹幕初始横向随机范围（进入点的随机区间）
const START_X_MIN = 360;
const START_X_MAX = 440;
// 弹幕纵向随机范围（弹幕层高 200，中心为 0）
const RANDOM_Y_MIN = -90;
const RANDOM_Y_MAX = 90;
// 弹幕划过时长（ms）
const DANMU_DURATION = 2600;

// 单条「+1 功德」弹幕（记录身份与随机位置，动画由子组件完成）
interface Danmaku {
  id: number;     // 唯一 id
  y: number;      // 纵向随机偏移（中心 0）
  startX: number; // 横向进入位置（随机）
}

/**
 * 单条弹幕子组件：进入后从右向左匀速划出
 */
@Component
struct DanmakuItem {
  @Prop yPos: number = 0;                          // 纵向位置（父组件传入）
  @Prop startX: number = SCREEN_RIGHT;             // 横向进入位置（父组件传入）
  @State x: number = SCREEN_RIGHT;                 // 当前横向位移

  aboutToAppear(): void {
    // 用传入的进入位置作为初始横坐标
    this.x = this.startX;
    // 等待首帧渲染后，用显式动画驱动从右向左
    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: DANMU_DURATION,
        curve: Curve.Linear
      }, () => {
        this.x = SCREEN_LEFT;
      });
    }, 50);
  }

  build() {
    Text('+1 功德')
      .fontSize(24)
      .fontWeight(FontWeight.Bold)
      .fontColor('rgba(255,255,255,0.72)')
      .fontStyle(FontStyle.Italic)
      .letterSpacing(1)
      .translate({
        x: this.x,
        y: this.yPos
      })
  }
}

@Component
export struct WoodenFishPage {
  @State count: number = 0;                    // 敲击次数
  @State danmakuList: Danmaku[] = [];           // 当前屏幕上的弹幕
  @State isHit: boolean = false;               // 木鱼按压反馈
  @State vibrateEnabled: boolean = true;        // 是否启用震动（默认开启）
  private prefs: preferences.Preferences | null = null; // 持久化实例
  private seqId: number = 0;                   // 弹幕自增 id
  private timerIds: number[] = [];             // 定时器句柄，清理用
  private hitTimerId: number = -1;             // 按压回弹定时器

  aboutToAppear(): void {
    this.loadCount();
  }

  aboutToDisappear(): void {
    this.timerIds.forEach((id: number) => clearTimeout(id));
    this.timerIds = [];
    if (this.hitTimerId !== -1) {
      clearTimeout(this.hitTimerId);
      this.hitTimerId = -1;
    }
    // 关闭时确保数据落盘
    this.saveCount();
  }

  /** 从本地持久化加载计数与震动开关 */
  async loadCount(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.prefs = await preferences.getPreferences(context, PREF_NAME);
      const value = await this.prefs.get(KEY_COUNT, 0);
      this.count = value as number;
      const vibrate = await this.prefs.get(KEY_VIBRATE, true);
      this.vibrateEnabled = vibrate as boolean;
    } catch (err) {
      console.error(`[WoodenFish] load count failed: ${JSON.stringify(err)}`);
    }
  }

  /** 保存计数到本地 */
  async saveCount(): Promise<void> {
    try {
      if (this.prefs === null) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        this.prefs = await preferences.getPreferences(context, PREF_NAME);
      }
      await this.prefs.put(KEY_COUNT, this.count);
      await this.prefs.flush();
    } catch (err) {
      console.error(`[WoodenFish] save count failed: ${JSON.stringify(err)}`);
    }
  }

  /** 保存震动开关到本地 */
  async saveVibrate(): Promise<void> {
    try {
      if (this.prefs === null) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        this.prefs = await preferences.getPreferences(context, PREF_NAME);
      }
      await this.prefs.put(KEY_VIBRATE, this.vibrateEnabled);
      await this.prefs.flush();
    } catch (err) {
      console.error(`[WoodenFish] save vibrate failed: ${JSON.stringify(err)}`);
    }
  }

  /** 切换震动开关 */
  toggleVibrate(): void {
    this.vibrateEnabled = !this.vibrateEnabled;
    this.saveVibrate();
  }

  /** 触发一次弱震动 */
  triggerVibrate(): void {
    if (!this.vibrateEnabled) {
      return;
    }
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 30
      }, {
        id: 0,
        usage: 'physicalFeedback'
      });
    } catch (err) {
      console.error(`[WoodenFish] vibrate failed: ${JSON.stringify(err)}`);
    }
  }

  /** 重置计数 */
  resetCount(): void {
    this.count = 0;
    this.saveCount();
  }

  /** 点击木鱼：计数 + 弹幕 + 震动 + 按压反馈 */
  onTap(): void {
    this.count += 1;
    this.saveCount();

    // 1. 生成弹幕
    this.spawnDanmaku();

    // 2. 触发震动（若开启）
    this.triggerVibrate();

    // 3. 木鱼按压反馈（缩放）
    this.isHit = true;
    if (this.hitTimerId !== -1) {
      clearTimeout(this.hitTimerId);
    }
    this.hitTimerId = setTimeout(() => {
      this.hitTimerId = -1;
      this.isHit = false;
    }, 140);
  }

  /** 生成一条「+1 功德」弹幕：随机出现位置，动画结束后移除 */
  spawnDanmaku(): void {
    const id = this.seqId++;

    // 随机纵向位置与横向进入点
    const y = Math.floor(Math.random() * (RANDOM_Y_MAX - RANDOM_Y_MIN + 1)) + RANDOM_Y_MIN;
    const startX = Math.floor(Math.random() * (START_X_MAX - START_X_MIN + 1)) + START_X_MIN;

    const item: Danmaku = { id: id, y: y, startX: startX };
    this.danmakuList = this.danmakuList.concat(item);

    // 动画结束后移除该弹幕
    const t = setTimeout(() => {
      this.danmakuList = this.danmakuList.filter((d: Danmaku) => d.id !== id);
    }, DANMU_DURATION + 300);
    this.timerIds.push(t);
  }

  /** 木鱼（Image）：可点击（不含弹幕，避免弹幕跟着缩放） */
  @Builder
  fishBuilder() {
    Image($r('app.media.fish'))
      .width(280)
      .height(280)
      .objectFit(ImageFit.Contain)
      .scale(this.isHit ? { x: 0.92, y: 0.92 } : { x: 1, y: 1 })
      .animation({ duration: 140, curve: Curve.EaseIn })
      .onClick(() => {
        this.onTap();
      })
  }

  /** 弹幕层：位于木鱼上方区域，从右向左划过的「+1 功德」 */
  @Builder
  danmakuBuilder() {
    Stack() {
      ForEach(this.danmakuList, (item: Danmaku) => {
        DanmakuItem({ yPos: item.y, startX: item.startX })
      }, (item: Danmaku) => item.id.toString())
    }
    .width('100%')
    .height(200)
    .clip(true)
  }

  build() {
    Column() {
      // 顶部工具条：左侧重置按钮，中间震动开关，右侧计数器
      Row() {
        Button() {
          Column() {
            Text('⟲')
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
            Text('重置')
              .fontSize(12)
              .fontColor('#CCCCCC')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
        }
        .width(64)
        .height(64)
        .backgroundColor('#1A1A1A')
        .borderRadius(32)
        .border({ width: 1, color: '#444444' })
        .onClick(() => {
          this.resetCount();
        })

        Blank()

        // 震动开关按钮
        Button() {
          Column() {
            Text('~')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.vibrateEnabled ? '#000000' : '#CCCCCC')
            Text(this.vibrateEnabled ? '震动开' : '震动关')
              .fontSize(12)
              .fontColor(this.vibrateEnabled ? '#000000' : '#888888')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
        }
        .width(64)
        .height(64)
        .backgroundColor(this.vibrateEnabled ? '#FFFFFF' : '#1A1A1A')
        .borderRadius(32)
        .border({ width: 1, color: '#444444' })
        .onClick(() => {
          this.toggleVibrate();
        })

        Blank()

        Text(this.count.toString())
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor('#1A1A1A')
          .borderRadius(24)
          .padding({ left: 22, right: 22, top: 12, bottom: 12 })
          .border({ width: 1, color: '#444444' })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      // 中间区域：弹幕层（上方）+ 木鱼（下方），垂直居中
      Column() {
        // 弹幕层
        this.danmakuBuilder()

        // 木鱼
        this.fishBuilder()
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
