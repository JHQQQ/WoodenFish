import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * 转盘页面
 * - 手动添加/删除类目（最多 12 个）
 * - 点击「开始」旋转转盘，随机选中一个类目
 * - 结果直接显示在转盘下方，不弹窗
 * - 类目列表持久化保存，重启后保持上次修改的样子
 */

// 持久化存储
const PREF_NAME = 'woodenfish_pref';
const KEY_CATEGORIES = 'wheel_categories';

// 默认类目（首次启动或读不到数据时使用）
const DEFAULT_CATEGORY_NAMES: string[] = ['吃饭', '学习', '运动', '休息', '加班', '逛街'];

// 最大类目数量（超过会放不下、文字重叠）
const MAX_CATEGORIES = 12;
// 提示文字显示时长（ms）
const TIP_DURATION = 2200;
// 转盘尺寸
const WHEEL_SIZE = 350;
// 转盘中心与半径
const WHEEL_CX = WHEEL_SIZE / 2;
const WHEEL_CY = WHEEL_SIZE / 2;
const WHEEL_RADIUS = WHEEL_SIZE / 2 - 10;
// 旋转动画时长
const SPIN_DURATION = 3000;
// 旋转整圈数（越多越有仪式感）
const SPIN_TURNS = 5;
// 扇形颜色（8 个，彩色且明暗交错，在黑色背景上鲜艳但不刺眼）
const SECTOR_COLORS: string[] = [
  '#E4572E', // 珊瑚红
  '#F4A259', // 暖橙
  '#F2C14E', // 金黄
  '#5FB49C', // 薄荷绿
  '#3D9BE9', // 天蓝
  '#6C63FF', // 靛紫
  '#C86FC9', // 品红
  '#E85D9E'  // 玫瑰粉
];

// 类目项（用于列表展示与删除）
interface CategoryItem {
  id: number;
  name: string;
}

@Component
export struct WheelPage {
  // 滚动状态回调：true=正在滚动（导航栏隐藏），false=停止滚动（导航栏显现）
  onScrollStateChange?: (isScrolling: boolean) => void;
  // 停止滚动的延时定时器句柄
  private scrollStopTimer: number = -1;

  @State categories: CategoryItem[] = [];
  @State rotation: number = 0;              // 转盘累计旋转角度
  @State result: string = '';               // 选中结果
  @State isSpinning: boolean = false;       // 是否正在旋转
  @State inputText: string = '';            // 添加类目输入框内容
  @State tipText: string = '';              // 页面内提示文字（空则不显示）
  private tipTimer: number = -1;            // 提示文字消失定时器
  private nextCatId: number = 0;            // 类目自增 id
  private prefs: preferences.Preferences | null = null;  // 持久化实例
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    // 先加载持久化的类目列表，再绘制（首绘在 Canvas onReady 中也会触发）
    this.loadCategories();
  }

  aboutToDisappear(): void {
    if (this.scrollStopTimer !== -1) {
      clearTimeout(this.scrollStopTimer);
      this.scrollStopTimer = -1;
    }
    if (this.tipTimer !== -1) {
      clearTimeout(this.tipTimer);
      this.tipTimer = -1;
    }
  }

  /** 从本地加载类目列表；无数据时使用默认类目 */
  async loadCategories(): Promise<void> {
    let names: string[] = DEFAULT_CATEGORY_NAMES;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.prefs = await preferences.getPreferences(context, PREF_NAME);
      const saved = await this.prefs.get(KEY_CATEGORIES, '');
      const raw = saved as string;
      if (raw.length > 0) {
        // 用换行符分隔存储，避免 JSON 解析与类型断言
        const parsed = raw.split('\n');
        const valid: string[] = [];
        for (let i = 0; i < parsed.length; i++) {
          const one = parsed[i].trim();
          if (one.length > 0) {
            valid.push(one);
          }
        }
        if (valid.length > 0) {
          names = valid;
        }
      }
    } catch (err) {
      console.error(`[Wheel] load categories failed: ${JSON.stringify(err)}`);
      names = DEFAULT_CATEGORY_NAMES;
    }
    // 重建类目数组并分配 id
    const list: CategoryItem[] = [];
    for (let i = 0; i < names.length; i++) {
      list.push({ id: i, name: names[i] });
    }
    this.nextCatId = list.length;
    this.categories = list;
    this.redraw();
  }

  /** 保存类目列表到本地（名称用换行符分隔） */
  async saveCategories(): Promise<void> {
    try {
      if (this.prefs === null) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        this.prefs = await preferences.getPreferences(context, PREF_NAME);
      }
      const names: string[] = [];
      for (let i = 0; i < this.categories.length; i++) {
        names.push(this.categories[i].name);
      }
      await this.prefs.put(KEY_CATEGORIES, names.join('\n'));
      await this.prefs.flush();
    } catch (err) {
      console.error(`[Wheel] save categories failed: ${JSON.stringify(err)}`);
    }
  }

  /** 处理滚动事件：滚动中隐藏导航栏，停止 300ms 后显现 */
  private handleScroll(): void {
    if (this.onScrollStateChange !== undefined) {
      this.onScrollStateChange(true);
    }
    // 防抖：滚动停止 300ms 后才视为停止
    if (this.scrollStopTimer !== -1) {
      clearTimeout(this.scrollStopTimer);
    }
    this.scrollStopTimer = setTimeout(() => {
      this.scrollStopTimer = -1;
      if (this.onScrollStateChange !== undefined) {
        this.onScrollStateChange(false);
      }
    }, 300);
  }

  /** 绘制转盘 */
  private drawWheel(): void {
    const n = this.categories.length;
    // 每次绘制前先清空画布，避免扇形叠加
    this.ctx.clearRect(0, 0, WHEEL_SIZE, WHEEL_SIZE);
    if (n === 0) {
      // 无类目时不绘制
      return;
    }
    const sectorDeg = 360 / n;
    // 从顶部（12 点钟，即 -90 度）开始顺时针排列
    for (let i = 0; i < n; i++) {
      const startAngle = (-90 + i * sectorDeg) * Math.PI / 180;
      const endAngle = (-90 + (i + 1) * sectorDeg) * Math.PI / 180;
      const color = SECTOR_COLORS[i % SECTOR_COLORS.length];

      // 绘制扇形
      this.ctx.beginPath();
      this.ctx.moveTo(WHEEL_CX, WHEEL_CY);
      this.ctx.arc(WHEEL_CX, WHEEL_CY, WHEEL_RADIUS, startAngle, endAngle);
      this.ctx.closePath();
      this.ctx.fillStyle = color;
      this.ctx.fill();
      // 扇形分隔线：深色描边，让彩色扇形层次更分明
      this.ctx.strokeStyle = 'rgba(0, 0, 0, 0.45)';
      this.ctx.lineWidth = 2;
      this.ctx.stroke();

      // 绘制类目文字：垂直于扇面，沿扇形中轴线排列
      // 文字随扇形一起旋转，起始端固定在外缘（圆弧）侧，
      // 这样扇形转到顶部指针位置时，从指针处读到的字序始终是正的
      const midAngle = (-90 + i * sectorDeg + sectorDeg / 2) * Math.PI / 180;
      const name = this.categories[i].name;
      const charCount = name.length;
      // 字号受扇形张角与字数双重约束，避免溢出重叠
      const fontSize = this.calcFontSize(charCount, sectorDeg);

      this.ctx.save();
      // 原点移到圆心，并旋转到扇形中轴方向
      this.ctx.translate(WHEEL_CX, WHEEL_CY);
      this.ctx.rotate(midAngle);

      this.ctx.font = `bold ${fontSize}vp sans-serif`;
      this.ctx.textAlign = 'center';
      this.ctx.textBaseline = 'middle';
      this.ctx.shadowColor = 'rgba(0, 0, 0, 0.35)';
      this.ctx.shadowBlur = 4;
      this.ctx.fillStyle = '#FFFFFF';

      // 沿中轴线排列；起始端固定在外缘侧，向圆心方向依次排列
      const lineHeight = fontSize * 1.02;
      const totalLen = lineHeight * charCount;
      const innerLimit = WHEEL_RADIUS * 0.22;
      const outerLimit = WHEEL_RADIUS * 0.94;
      const usableLen = outerLimit - innerLimit;
      // 整串居中：算出最外缘那个字的半径
      let firstR = outerLimit - (usableLen - totalLen) / 2;
      if (firstR > outerLimit) {
        firstR = outerLimit;
      }

      for (let c = 0; c < charCount; c++) {
        // 从外缘向内递减排列：第 0 个字最靠外
        const r = firstR - c * lineHeight;
        this.ctx.save();
        // 移到该字在半径上的位置
        this.ctx.translate(r, 0);
        // 字旋转 90°，使笔画上下方向垂直于扇面
        this.ctx.rotate(Math.PI / 2);
        this.ctx.fillText(name.substring(c, c + 1), 0, 0);
        this.ctx.restore();
      }

      this.ctx.restore();
    }
  }

  /**
   * 计算扇形竖排文字的字号（单位 vp）
   * 竖排文字占用：水平 = 字号（一个字宽）；垂直 = 字号 * 1.02 * 字数
   * 需保证该占位能放进扇形，避免溢出到相邻扇形造成重叠
   */
  private calcFontSize(charCount: number, sectorDeg: number): number {
    const chars = charCount > 0 ? charCount : 1;

    // 可用水平宽度：扇形在中段的弦长（张角越小越窄）
    const halfRad = sectorDeg * Math.PI / 180 / 2;
    const midR = WHEEL_RADIUS * 0.62;
    // 扇形在半径 midR 处的弦长近似
    const chord = 2 * midR * Math.sin(halfRad);
    // 字宽不能超过弦长的 70%
    const sizeByWidth = chord * 0.70;

    // 可用垂直高度：从圆心附近到接近外缘的径向长度（竖排沿垂直方向铺开）
    // 取较保守的可用高度，避免顶出转盘边缘或压到圆心
    const usableHeight = WHEEL_RADIUS * (0.92 - 0.22);
    // 整串高度 = 字号 * 1.02 * 字数，不能超过可用高度
    const sizeByHeight = usableHeight / (chars * 1.02);

    let size = Math.min(sizeByWidth, sizeByHeight);
    // 限制字号上下限，兼顾美观与可读
    if (size > 30) {
      size = 30;
    }
    if (size < 11) {
      size = 11;
    }
    return Math.floor(size);
  }

  /** 类目变化后延迟绘制（等状态更新完成） */
  private redraw(): void {
    setTimeout(() => {
      this.drawWheel();
    }, 0);
  }

  /** 添加类目 */
  addCategory(): void {
    const name = this.inputText.trim();
    if (name.length === 0) {
      this.showTip('请输入类目名称');
      return;
    }
    if (this.categories.length >= MAX_CATEGORIES) {
      this.showTip(`最多只能添加 ${MAX_CATEGORIES} 个类目`);
      return;
    }
    const item: CategoryItem = { id: this.nextCatId++, name: name };
    this.categories = this.categories.concat(item);
    this.inputText = '';
    this.redraw();
    this.saveCategories();
  }

  /** 显示页面内提示文字，TIP_DURATION 毫秒后自动消失 */
  private showTip(msg: string): void {
    this.tipText = msg;
    if (this.tipTimer !== -1) {
      clearTimeout(this.tipTimer);
    }
    this.tipTimer = setTimeout(() => {
      this.tipTimer = -1;
      this.tipText = '';
    }, TIP_DURATION);
  }

  /** 删除类目 */
  removeCategory(id: number): void {
    if (this.isSpinning) {
      return;
    }
    this.categories = this.categories.filter((c: CategoryItem) => c.id !== id);
    this.result = '';
    this.redraw();
    this.saveCategories();
  }

  /** 开始旋转：随机选中一个类目并旋转到指针位置 */
  startSpin(): void {
    const n = this.categories.length;
    if (n < 2 || this.isSpinning) {
      return;
    }
    this.isSpinning = true;
    this.result = '';

    // 随机选中一个类目
    const targetIndex = Math.floor(Math.random() * n);
    const sectorDeg = 360 / n;

    // 让目标扇形【中心】精确对准顶部指针：
    // 扇形中心在转盘坐标中为 (i + 0.5) * sectorDeg（自顶部顺时针），
    // 顺时针旋转 rotation 后需满足 rotation ≡ -(i + 0.5) * sectorDeg (mod 360)
    const desiredMod = this.normalizeDeg(360 - (targetIndex + 0.5) * sectorDeg);
    const currentMod = this.normalizeDeg(this.rotation);
    // 还需补足的角度（保证顺时针继续转）
    const delta = this.normalizeDeg(desiredMod - currentMod);
    const targetRotation = this.rotation + SPIN_TURNS * 360 + delta;

    this.getUIContext().animateTo({
      duration: SPIN_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.isSpinning = false;
        this.result = this.categories[targetIndex].name;
      }
    }, () => {
      this.rotation = targetRotation;
    });
  }

  /** 将角度规范化到 [0, 360) */
  private normalizeDeg(deg: number): number {
    const r = deg % 360;
    return r < 0 ? r + 360 : r;
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        // 标题
        Text('转盘决定')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .margin({ top: 24 })

        // 转盘 + 指针
        Stack({ alignContent: Alignment.Center }) {
          // 转盘（随 rotation 旋转）
          Canvas(this.ctx)
            .width(WHEEL_SIZE)
            .height(WHEEL_SIZE)
            .onReady(() => {
              // Canvas 就绪后首次绘制
              this.drawWheel();
            })
            .rotate({ angle: this.rotation, centerX: '50%', centerY: '50%' })

          // 外圈描边
          Circle({ width: WHEEL_SIZE, height: WHEEL_SIZE })
            .fillOpacity(0)
            .stroke('rgba(255, 255, 255, 0.65)')
            .strokeWidth(3)

          // 顶部指针（不旋转）：纯白色 + 深色描边，与转盘所有颜色都区分明显
          Text('▼')
            .fontSize(36)
            .fontColor('#FFFFFF')
            .textShadow({ radius: 6, color: 'rgba(0, 0, 0, 0.85)', offsetX: 0, offsetY: 0 })
            .position({ x: WHEEL_CX - 18, y: 0 })
        }
        .width(WHEEL_SIZE)
        .height(WHEEL_SIZE)

        // 结果展示
        Text(this.result.length > 0 ? `选中：${this.result}` : '点击开始随机选择')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.result.length > 0 ? '#F2C14E' : '#888888')
          .margin({ top: 8 })

        // 开始按钮（渐变彩色，与转盘呼应）
        Button(this.isSpinning ? '旋转中...' : '开始')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .linearGradient({
            angle: 135,
            colors: [['#6C63FF', 0.0], ['#3D9BE9', 1.0]]
          })
          .borderRadius(28)
          .width(200)
          .height(60)
          .enabled(!this.isSpinning)
          .onClick(() => {
            this.startSpin();
          })

        // 类目管理
        Column({ space: 12 }) {
          Row() {
            Text('管理类目')
              .fontSize(19)
              .fontWeight(FontWeight.Medium)
              .fontColor('#CCCCCC')

            Blank()

            // 类目数量提示（达到上限时变红）
            Text(`${this.categories.length} / ${MAX_CATEGORIES}`)
              .fontSize(15)
              .fontColor(this.categories.length >= MAX_CATEGORIES ? '#FF6B6B' : '#888888')
          }
          .width('100%')

          // 页面内提示文字（有内容时才显示）
          if (this.tipText.length > 0) {
            Text(this.tipText)
              .fontSize(15)
              .fontColor('#FF6B6B')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 4, bottom: 4 })
          }

          // 添加类目输入行
          Row({ space: 10 }) {
            TextInput({ placeholder: '输入类目名称', text: this.inputText })
              .onChange((value: string) => {
                this.inputText = value;
              })
              .fontSize(18)
              .fontColor('#FFFFFF')
              .placeholderColor('#888888')
              .backgroundColor('#1A1A1A')
              .borderRadius(22)
              .height(52)
              .layoutWeight(1)
              .padding({ left: 16, right: 16 })

            Button('添加')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .linearGradient({
                angle: 135,
                colors: [['#5FB49C', 0.0], ['#3D9BE9', 1.0]]
              })
              .borderRadius(22)
              .height(52)
              .padding({ left: 22, right: 22 })
              .onClick(() => {
                this.addCategory();
              })
          }
          .width('100%')

          // 类目列表（可删除）
          if (this.categories.length > 0) {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.categories, (item: CategoryItem) => {
                Row({ space: 8 }) {
                  Text(item.name)
                    .fontSize(17)
                    .fontColor('#FFFFFF')
                  Text('✕')
                    .fontSize(15)
                    .fontColor('#888888')
                }
                .backgroundColor('#1A1A1A')
                .borderRadius(18)
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.removeCategory(item.id);
                })
              }, (item: CategoryItem) => item.id.toString())
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20 })
        .margin({ bottom: 24 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .scrollBar(BarState.Off)
    // 滚动时通知父组件隐藏导航栏，停止后显现
    .onScroll((xOffset: number, yOffset: number) => {
      this.handleScroll();
    })
  }
}
