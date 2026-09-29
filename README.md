# KN-Web

Kerr–Newman 黑洞 WebGPU 渲染与在线科普演示

物理实现遵照 baopinshui `BlackHole_common.glsl`。后处理已接通：星空 → 半分辨率 KN 预计算 → 全分辨率合成 / 边缘重追踪 → HDR / TAA / Bloom / 显示映射。支持星空 / 方向网格切换及 Schwarzschild、Kerr、KN 预设。吸积盘、最大延拓仍待实现。

## 启动

Node.js 22.18+，npm：

```sh
npm ci
npm run dev
```

打开 http://127.0.0.1:5173/ 。本地使用支持 WebGPU 的桌面 Chrome / Edge；远程访问需要 HTTPS。

```sh
npm test             # 53 项 CPU 测试：相机、输入、uniform、cubemap 与异步加载清理
npm run build        # TypeScript 检查 + Vite 静态构建
npm run preview      # http://127.0.0.1:4173/
npm run test:physics # GLSL / WGSL 实际 GPU 对照 + 网格离屏绘制
npm run test:sky     # 星空像素 / mip 校验 + 三种黑洞与自旋 / Q 对照
npm run test:temporal # NPGS C++ / GLM 时间权重、运动判据和速度对照
npm run test:post    # 含上述回归 + 生产后处理 GPU 回放 + GLSL TAA / Bloom 对照
npm run test:spectrum # 含上述回归 + GLSL 颜色频移对照与强频移 HDR 验证
npm run test:trace    # 原 GLSL 预算、回转退出、终止打包与 WGSL 控制流对照
npm run test:prepass  # 含上述回归 + 13 组预计算 / 合成场景及原 GLSL 初始采样对照
```

`test:physics` 是可选开发验证工具，需要 macOS Metal、Rust/Cargo、Python 3、glslangValidator；不属于前端运行依赖。`test:sky` / `test:post` 另需 Python Pillow；TAA 宿主对照另需 clang++ 和 GLM（当前路径 `/opt/homebrew/include`）。原函数快照位于 `reference/`；星空资产位于 `public/cubemaps/universe0/`，校验清单位于 `reference/universe0.json`。

## 操作

- 手机触屏：单指拖动对应左键；双指同向拖动对应右键；双指捏合对应滚轮。轨道模式下张开拉近、合拢拉远，可以同时捏合与转动视角。自由模式沿用鼠标规则：单指转向，捏合调整移动速度，双指平移不转向。

- 点击画布聚焦，**T 键切换「轨道绕转 + 独立摆头」与「自由视角」**；面板显示当前模式。编辑参数时不会误触切换，长按 T 不重复切换。
- 轨道模式（默认）：左键 / WASD 绕黑洞公转，右键只调整摄像机视角，中键平滑回正；绕转保留右键偏移。
- 自由模式：左键原地转向，WASD 前后左右，RF 沿相机上方向升降，QE 滚转，Shift 加速；右键摆头和中键回正仅在轨道模式生效。
- 两种模式的绕转、摆头、自由转向与滚转均惯性滑停：松手后继续衰减剩余转角。采用实际生效的旋转系数 `1`、滚转系数 `1/3`。
- 切换保留位置与完整朝向，并清除拖拽、按键、剩余转角与距离过渡。轨道模式滚轮平滑拉近 / 拉远黑洞；自由模式滚轮调整移动速度，均沿用每档 `1.2` 的倍率。**FOV 只通过面板调整**，滚轮不再缩放整个视野。
- 参数框调整质量 M / M☉、无量纲 a* / Q*、quality 与输出尺寸模式。
- 默认开启「跟随窗口尺寸」，输出及相机宽高比随窗口变化；关闭后可用「固定宽度 / 高度」指定像素数。预计算每轴取输出的一半并向下取整（至少 1 px）。关闭「半分辨率预计算」可对照全分辨率逐像素追踪。诊断视图始终以全分辨率绘制。
- 「KN 引力透镜」显示追踪后的星空；「背景」可切换方向网格；「原背景」显示无引力对照；「积分步数 / 终止状态」检查积分情况。
- 「黑洞预设」：Schwarzschild (0,0)、Kerr (0.95,0)、KN (0.8,0.4)，只修改 a* / Q*，保留相机。
- 「颜色频移」默认开启：GLSL 光谱映射、Shift⁴、背景亮度倍率，频移来自光线初始守恒能量；默认上限 1.5、亮度倍率 2。关闭可对照原色；「原背景」使用 shift=1。
- 「后处理」可独立开关 TAA / Bloom，调整曝光 EV、Gamma、泛光强度。沿用 NPGS 无抖动、时间相关的历史权重，运动超过原阈值时只使用当前帧。可调时间倍率，面板显示当前帧权重；关闭后处理查看原色。
- 「重置相机」恢复轨道模式，回到 `(0,2,10) Rs` 并朝向原点；「校验 GPU 参数」再次验证 CPU/WGSL uniform 快照。
- 保留 Phase 0 的 UV、Phase 1 的相机网格和参数颜色视图用于回归检查。

进入视界、预算耗尽或回转过多均按原 Absorbed/Lost 状态输出黑色，星空自身也有暗像素。紫色表示范围不支持或数值异常。当前只追踪 `a*²+Q*²≤1` 且相机位于外部静态区的场景；超范围输入不会被静默修正。

坐标按 Rs 归一化，几何 `M=0.5`；固定相机 Rs 坐标时，单独改变太阳质量不改变透镜形状。quality 沿用原步长和预算公式，保留原严格 `Count > budget` 条件，已移除额外的 1024 步上限。默认输出跟随画布窗口尺寸（CSS 像素），不额外乘 Retina DPR，对齐 macOS 禁用 Retina framebuffer 缩放的行为。1280×960 是初始窗口尺寸，并非固定比例；Web 保留此值作为固定尺寸模式的初值。已移除 640 / 2048 px 输出限制；超过设备纹理限制时等比例缩小。尚未完成浏览器帧率基准或自适应优化。

## 验证现状

- 53 项 CPU 测试、TypeScript 和生产构建通过，覆盖轨道 / 摆头、T 切换、自由平移 / 滚转、惯性衰减、平滑回正，以及滚轮距离倍率 / 平滑、朝向保持、自由移动速度与生命周期清理。
- Apple M3 Pro / Metal：23 组GLSL vs WGSL 数值对照、31 条完整追踪探针、108 个六面朝向 / 颜色 / mip 探针、14 张完整管线离屏图通过。
- 自旋反转的阴影逐像素镜像；固定 a*=0.8 加电荷后阴影缩小；近临界光线展示绕转行为。
- 16 组后处理图、32 帧原生 GPU 回放通过；TAA 混合 / 重置、HDR 数值、Bloom、曝光、Gamma 与方向校验见 [Phase 6 报告](docs/phase6-post.md)。
- Bloom 已对齐 `Bloom.comp.glsl` atlas 与 `ColorBlend.frag.glsl` bicubic 重建，移除额外阈值；51 次 HDR 阶段对照在本机逐值一致，最终显示最多相差 1/255，见 [Bloom 对齐记录](docs/bloom-alignment.md)。
- TAA 已迁移原时间权重、无抖动及运动判据：495 组 C++ / GLM 对照通过，12 个 TAA 帧的 GLSL / WGSL RGB 回读一致；生命周期与 alpha 边界见 [TAA 对齐记录](docs/taa-alignment.md)。
- 追踪预算 / 终止状态：147 组原 GLSL 控制流对照通过；实际 RK4 压力探针可超过 1024 步，详见 [追踪预算对齐记录](docs/trace-budget-alignment.md)。
- 实现边界、原生 GPU 渲染与误差记录见 [Phase 3 报告](docs/phase3-background.md) 和 [Phase 2 迁移报告](docs/phase2-port.md)。
- 半分辨率流程：13 组 GPU 场景通过，1280×960 测试尺寸下约 2%–2.6% 像素重新追踪；奇数尺寸传参和像素中心采样已对齐；984,009 条初始光线与原 GLSL 回读逐值一致，手动插值、边缘判据及极小尺寸回归通过，见 [预计算迁移记录](docs/prepass-port.md)。
- **浏览器工具未连接**，ImageBitmap 上传、Canvas 显示、持续帧率、键鼠、resize、热更新与设备恢复仍待浏览器验收。原生 GPU 测试不能替代浏览器宿主测试。

浏览器验收时检查：启动状态与 GPU 参数回读成功；切换三种物理参数组合；拖动和移动引起正常透镜变化；改变 quality 检查临界曲线和积分步数变化；默认窗口 resize 后输出 / 预计算尺寸与投影比例同步更新，固定模式仍保持指定宽高；切后台后停止移动且返回不跳跃；不支持 WebGPU 时有可读错误和重试入口。

## 主要入口

```text
src/shaders/geometry.wgsl       KN 几何、初始动量、Hamilton 与 RK4
src/shaders/coordinates.wgsl    KS chart 变换、原水平 FOV 光线生成
src/shaders/geodesic.wgsl       外部静态观者主追踪循环
src/shaders/prepass.wgsl       双输出预计算、手动插值、原边缘重追踪判据
src/renderer/scene-passes.ts   半分辨率 / 全分辨率 pass 与纹理生命周期
src/renderer/render-size.ts    窗口 / 固定输出与预计算尺寸
src/shaders/fullscreen.wgsl     输出、cubemap 采样和诊断
src/renderer/renderer.ts        WebGPU 生命周期、尺寸和逐帧调度
src/renderer/post-processing.ts HDR、TAA、Bloom 与显示 pass
src/renderer/temporal.ts        NPGS 时间权重、运动判据与生命周期
src/renderer/background.ts     原星空 / 网格 cubemap 与 mip
src/renderer/cubemap-loader.ts 六面并行解码、校验、取消与清理
src/renderer/buffers.ts         uniform / bind group / GPU 回读
src/physics/parameters.ts       默认值与参数范围
src/camera/                     键鼠相机
reference/                     原始依据
```

[Uniform 布局](docs/uniform-layout.md)

本轮不部署。Phase 4/5 保留待办；背景颜色频移及亮度倍率已迁移，HDR 接收真实频移；详见 [颜色频移记录](docs/spectrum-port.md)。当前为静态观者，不含运动观者 Doppler 或吸积盘频移。TAA 采用时间相关混合和原运动阈值，不含运动重投影。
