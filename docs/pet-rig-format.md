# BoomPet 骨骼动作包格式

一个动作包是包含 `pet-rig.json` 和透明 PNG 部件的文件夹。进入
“设置 → 宠物 → 骨骼、动作与路线配置”，点击“导入动作包…”即可加载。
导入前 BoomPet 会校验配置和全部素材，失败时继续保留当前宠物。

仓库中的
[`Sources/BoomPet/Resources/DefaultPetRig`](../Sources/BoomPet/Resources/DefaultPetRig)
是一套可直接复制修改的完整示例。

![内置动作包的 idle、walk、run、crawl 关键帧](boompet-rig-preview.png)

## 最小结构

```text
MyPetRig/
├── pet-rig.json
├── body.png
├── head.png
├── ear-left.png
├── ear-right.png
├── leg-front-left.png
├── leg-front-right.png
├── leg-rear-left.png
├── leg-rear-right.png
└── tail.png
```

文件名可以自定义，由 `parts[].file` 关联。建议所有图片采用透明背景，
并在肢体与身体连接处保留少量重叠。

## 顶层字段

| 字段 | 说明 |
| --- | --- |
| `formatVersion` | 当前固定为 `1` |
| `name` | 动作包名称 |
| `canvas` | 设计坐标系宽高；内置示例为 `154×154` |
| `direction` | 默认朝向和是否随移动方向镜像 |
| `movement` | 自动巡游路线、速度、动作权重及停顿 |
| `parts` | 素材、层级、基础位置、尺寸和旋转锚点 |
| `animations` | 动作名称、周期及各部件关键帧 |

## 部件

```json
{
  "id": "earLeft",
  "file": "ear-left.png",
  "parent": "head",
  "zIndex": 44,
  "frame": { "x": 27, "y": 116, "width": 34, "height": 38 },
  "anchor": { "x": 0.72, "y": 0.14 }
}
```

- 坐标原点在画布左下角。
- `zIndex` 越大越靠前。
- `anchor` 使用 `0...1` 的部件内部比例坐标。
- `parent` 可省略。设置后会继承父节点的位移、旋转和缩放。例如耳朵、
  眼睛和嘴以头部为父节点，头部抬起时它们会一起移动。
- 所有素材路径必须是动作包目录内的单个文件名，不允许引用目录外文件。

## 关键帧

```json
{
  "part": "legFrontLeft",
  "keyframes": [
    { "time": 0, "rotation": -42, "x": -5, "scaleY": 1.08 },
    { "time": 0.5, "rotation": 44, "x": 5, "scaleY": 0.92 },
    { "time": 1, "rotation": -42, "x": -5, "scaleY": 1.08 }
  ]
}
```

`time` 是一次循环中的 `0...1` 比例。支持：

- `x`、`y`：相对基础位置的偏移。
- `rotation`：角度，正值逆时针。
- `scaleX`、`scaleY`：水平和垂直缩放，默认 `1`。

BoomPet 会在线性关键帧之间插值，并在结尾无缝回到开头。当前自动行为识别
`idle`、`walk`、`run`、`crawl` 四个动作名；缺少某个动作时回退到 `idle`。

## 方向与路线

```json
{
  "direction": {
    "defaultFacing": "right",
    "mirrorWithMovement": true
  },
  "movement": {
    "horizontalMargin": 0.32,
    "verticalMargin": 0.20,
    "maxVerticalShift": 52,
    "walkSpeed": 160,
    "runSpeed": 235,
    "crawlSpeed": 105,
    "walkWeight": 38,
    "runWeight": 42,
    "crawlWeight": 20,
    "pauseMinimum": 0.7,
    "pauseMaximum": 2.1
  }
}
```

- `horizontalMargin`、`verticalMargin` 乘以宠物窗口尺寸，形成自动巡游安全区。
- `maxVerticalShift` 控制每段路线最多改变多少纵向坐标，避免斜向漂浮。
- 三种 `Speed` 是每秒设计点速度。
- 三种 `Weight` 控制随机动作比例；长距离移动会额外提高奔跑概率。
- `pauseMinimum`、`pauseMaximum` 控制两段运动之间的停顿秒数。
- 鼠标进入宠物范围时始终暂停，移开后再恢复。

## 预览配置

开发构建后可以生成四种动作、四个关键帧的联系表：

```bash
swift run BoomPet --render-rig-preview /tmp/boompet-rig-preview.png
```

正式应用也支持相同参数：

```bash
/Applications/BoomPet.app/Contents/MacOS/BoomPet \
  --render-rig-preview ~/Desktop/boompet-rig-preview.png
```
