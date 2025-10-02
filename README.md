开启插件后会自动在根目录生成一个labels.cfg

#### 以下为示例配置
[labels]
player="玩家"
player.gd="玩家脚本"
[path_labels]
component/pattern="模版"

labels 中的键值会全局匹配，只要名称符合就会为其添加标签
path_labels  中的键值必须符合路径才会为其添加标签
path_labels 优先级高于 labels

主要用于在保留英文路径的前提下使整个项目路径变的更可读entity【对象实体】

又或是对文件夹进行详细的描述而不污染路径【仅存放A类场景】【跟踪寻路实现】【随机寻路实现】

对于同名文件进行备注区分，component【通用组件】、component【角色组件】

又或是打上特定的状态标签【待实现】【废弃】【仅用于特定场景】【必须和XX配合使用】
