import uiMaterial from '@ohos.arkui.uiMaterial';
import { WoodenFishPage } from './WoodenFishPage';
import { WheelPage } from './WheelPage';

/**
 * 应用主容器：底部沉浸光感（Immersive Light）悬浮页签
 * 使用系统沉浸式材质 ImmersiveMaterial（API 26）
 * - 底部悬浮推荐 THIN 样式 + 渐变蒙层
 * - Tab 1：转盘；Tab 2：木鱼
 */

// 当前选中的 Tab 下标
const TAB_WHEEL = 0;
const TAB_FISH = 1;

@Entry
@Component
struct Index {
  @State currentIndex: number = TAB_WHEEL;   // 当前 Tab
  @State isBarVisible: boolean = true;        // 导航栏是否可见
  private tabsController: TabsController = new TabsController();

  /**
   * 沉浸光感材质（底部悬浮用 THIN 样式）
   * interactive: 交互形变；lightEffect: 触摸光感反馈
   * 用 try-catch 保护：设备不支持时降级，避免崩溃
   */
  private immersiveMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;

  aboutToAppear(): void {
    try {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        this.immersiveMaterial = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true,
          lightEffect: {}
        });
      }
    } catch (err) {
      console.error(`[WoodenFish] create ImmersiveMaterial failed: ${JSON.stringify(err)}`);
      this.immersiveMaterial = undefined;
    }
  }

  /**
   * 子页面滚动状态变化：滚动时隐藏导航栏，停止时显现
   * 用 animateTo 做平滑过渡动画
   */
  private onScrollStateChange(isScrolling: boolean): void {
    const visible = !isScrolling;
    if (this.isBarVisible === visible) {
      return;
    }
    this.isBarVisible = visible;
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.EaseInOut
    }, () => {
      // 隐藏时向下平移出屏幕，同时淡出
      this.tabsController.setTabBarTranslate({ y: visible ? 0 : 120 });
      this.tabsController.setTabBarOpacity(visible ? 1 : 0);
    });
  }

  /**
   * 页签项
   * @param iconOffsetY 图标垂直微调（不同符号的字形位置不同，需单独补偿）
   */
  @Builder
  tabItem(title: string, icon: string, index: number, iconOffsetY: number) {
    Column() {
      // 图标固定高度 + 单独垂直微调，保证两个页签的图标视觉对齐
      // （不同符号的字形在行框内位置不同，仅靠 height 无法对齐）
      Text(icon)
        .fontSize(24)
        .fontColor(this.currentIndex === index ? '#FFFFFF' : '#999999')
        .height(30)
        .textAlign(TextAlign.Center)
        .offset({ y: iconOffsetY })
      Text(title)
        .fontSize(15)
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? '#FFFFFF' : '#999999')
        .height(20)
        .textAlign(TextAlign.Center)
        .margin({ top: 2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 底部留白，把内容整体顶上去（修正页签栏内部布局导致的内容偏下）
    .padding({ bottom: 14 })
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
        // Tab 1：转盘
        TabContent() {
          WheelPage({
            onScrollStateChange: (isScrolling: boolean) => {
              this.onScrollStateChange(isScrolling);
            }
          })
        }
        .tabBar(this.tabItem('转盘', '◎', TAB_WHEEL, 0))

        // Tab 2：木鱼
        TabContent() {
          WoodenFishPage()
        }
        .tabBar(this.tabItem('木鱼', '✦', TAB_FISH, -2))
      }
      // 沉浸光感悬浮样式：系统材质 + 透明蒙层 + 悬浮边距
      .barFloatingStyle({
        systemMaterial: this.immersiveMaterial,
        maskColor: Color.Transparent,
        // 边距越小，悬浮栏越宽
        barSideMargin: 8,
        barBottomMargin: 20
      })
      // 页签栏高度
      .barHeight(72)
      // 内容与页签栏重叠，让内容从材质下方透出
      .barOverlap(true)
      .scrollable(false)
      .animationDuration(200)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
