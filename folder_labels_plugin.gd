@tool
extends EditorPlugin

# 这个插件会读取 res://labels.cfg 中配置的映射，
# 将 FileSystem 面板里名称与键匹配的文件/文件夹右侧追加一个后缀。
# 例如 labels.cfg 中写入：
#   [labels]
#   player.gd = 玩家
#   [path_labels]
#   component/pattern = 模版
# 当 FileSystem 中出现名字为 player.gd 的文件时，就会在右侧显示“ 玩家”。
# path 标签需要与资源路径完全相同（相对路径，如 system/class/dialogue）。

## 配置文件路径
const CONFIG_PATH := "res://labels.cfg" # 映射配置文件路径
## FileSystemDock 实例
var file_system_dock: FileSystemDock
## EditorFileSystem 实例，用于监听资源刷新
var editor_fs
## 文件树信息
var tree_connections: Dictionary = {}
## 从配置文件读取的名称后缀映射
var labels_map: Dictionary = {}
var path_labels: Dictionary = {}

func _enter_tree() -> void:
	file_system_dock = get_editor_interface().get_file_system_dock()
	editor_fs = get_editor_interface().get_resource_filesystem()
	if editor_fs and not editor_fs.filesystem_changed.is_connected(_on_filesystem_changed):
		editor_fs.filesystem_changed.connect(_on_filesystem_changed)
	_load_labels()
	call_deferred("_connect_and_apply")

func _exit_tree() -> void:
	_disconnect_trees()
	if editor_fs and editor_fs.filesystem_changed.is_connected(_on_filesystem_changed):
		editor_fs.filesystem_changed.disconnect(_on_filesystem_changed)
	editor_fs = null
	file_system_dock = null
	labels_map.clear()
	path_labels.clear()

## 刷新和应用后缀
func _connect_and_apply() -> void:
	_connect_trees()
	_apply_labels_to_all()

## 更新文件树信息
func _connect_trees() -> void:
	if not file_system_dock:
		push_warning("[Folder Labels] FileSystemDock 未就绪")
		return
	var trees := _find_filesystem_trees()
	if trees.is_empty():
		push_warning("[Folder Labels] 未找到 FileSystem Tree，稍后重试")
		return
	for tree: Tree in trees:
		var id: int = tree.get_instance_id()
		if tree_connections.has(id):
			continue
		var collapse_callable := Callable(self, "_on_tree_item_collapsed").bind(tree)
		if not tree.item_collapsed.is_connected(collapse_callable):
			tree.item_collapsed.connect(collapse_callable)
		tree.set_column_expand(0, true)
		tree.set_column_clip_content(0, false)
		tree_connections[id] = {
			"tree": tree,
			"collapse_callable": collapse_callable,
		}

## 断开信号链接
func _disconnect_trees() -> void:
	for info in tree_connections.values():
		var tree: Tree = info.get("tree")
		var collapse_callable: Callable = info.get("collapse_callable")
		if tree and collapse_callable and tree.item_collapsed.is_connected(collapse_callable):
			tree.item_collapsed.disconnect(collapse_callable)
	tree_connections.clear()

## 找到所有 Tree 节点
func _find_filesystem_trees() -> Array:
	var result: Array = []
	if not file_system_dock:
		push_warning("未找到 FileSystemDock 实例")
		return result
	var queue: Array = [file_system_dock]
	while not queue.is_empty():
		var current = queue.pop_front()
		for child in current.get_children():
			if child is Tree:
				var path: String = child.get_path()
				if "/FileSystem/" in path:
					result.append(child)
			elif child is Node:
				queue.append(child)
	return result

## 目录展开或折叠时，部分 TreeItem 会重新生成，延迟刷新一次后缀
func _on_tree_item_collapsed(item: TreeItem, tree: Tree) -> void:
	if tree:
		call_deferred("_apply_labels_to_tree", tree)

## 重新扫描资源时重新加载配置并刷新所有 Tree。
func _on_filesystem_changed() -> void:
	_load_labels()
	_disconnect_trees()
	call_deferred("_connect_and_apply")

## 加载配置
func _load_labels() -> void:
	labels_map.clear()
	path_labels.clear()
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	# 没有配置则初始化配置
	if err == ERR_FILE_NOT_FOUND or err == ERR_DOES_NOT_EXIST:
		_create_default_config()
		err = cfg.load(CONFIG_PATH)
	if err != OK:
		push_warning("Folder Labels: 无法加载 %s (error %d)" % [CONFIG_PATH, err])
		return
	# 获取 labels
	var keys: PackedStringArray
	if cfg.has_section("labels"):
		keys = cfg.get_section_keys("labels")
	if keys:
		for key in keys:
			var value = cfg.get_value("labels", key, "")
			var suffix := String(value)
			if suffix.is_empty():
				continue
			labels_map[String(key)] = suffix
	# 获取 path_labels
	var path_keys: PackedStringArray
	if cfg.has_section("path_labels"):
		path_keys = cfg.get_section_keys("path_labels")
	if not path_keys.is_empty():
		for path_key in path_keys:
			var path_suffix := String(cfg.get_value("path_labels", path_key, ""))
			if path_suffix.is_empty():
				continue
			var normalized_path := _normalize_path(String(path_key))
			if normalized_path.is_empty():
				continue
			path_labels[normalized_path] = path_suffix

## 创建默认配置
func _create_default_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("labels", "player.gd", "玩家")
	cfg.set_value("path_labels", "component/pattern", "模版")
	var save_err := cfg.save(CONFIG_PATH)
	if save_err != OK:
		push_warning("Folder Labels: 无法创建默认配置 (%d)" % save_err)
	else:
		EditorInterface.get_resource_filesystem().scan()
		print("创建文件:",CONFIG_PATH)

## 清洗路径
func _normalize_path(path: String) -> String:
	var result := String(path).strip_edges()
	if result.is_empty():
		return ""
	if result.begins_with("res://"):
		result = result.substr(6)
	result = result.replace("\\", "/")
	while result.begins_with("./"):
		result = result.substr(2)
	while result.begins_with("/"):
		result = result.substr(1)
	while result.ends_with("/"):
		result = result.substr(0, result.length() - 1)
	return result

## 获取 TreeItem 路径
func _get_item_path(item: TreeItem) -> String:
	if not item:
		return ""
	var metadata = item.get_metadata(0)
	if typeof(metadata) == TYPE_STRING:
		var meta_str := String(metadata)
		if not meta_str.is_empty():
			return meta_str
	var tooltip = item.get_tooltip_text(0)
	if typeof(tooltip) == TYPE_STRING:
		var tooltip_str := String(tooltip)
		if not tooltip_str.is_empty():
			return tooltip_str
	return ""

## 对所有 Tree 进行后缀映射
func _apply_labels_to_all() -> void:
	for info in tree_connections.values():
		var tree: Tree = info.get("tree")
		if tree:
			_apply_labels_to_tree(tree)

## 后缀映射
func _apply_labels_to_tree(tree: Tree) -> void:
	var root: TreeItem = tree.get_root()
	if not root:
		return
	var stack: Array = [root]
	# 循环遍历 Tree
	while not stack.is_empty():
		var current: TreeItem = stack.pop_back()
		current.set_suffix(0, "")
		var suffix := ""
		# 验证路径匹配
		if not path_labels.is_empty():
			var resource_path := _normalize_path(_get_item_path(current))
			if not resource_path.is_empty() and path_labels.has(resource_path):
				suffix = String(path_labels[resource_path])
		# 如路径未匹配，验证标签匹配
		if suffix.is_empty():
			var name := current.get_text(0)
			if labels_map.has(name):
				suffix = String(labels_map[name])
		# 设置后缀
		if not suffix.is_empty():
			current.set_suffix(0, " " + suffix)
		# 深度循环
		var child := current.get_first_child()
		while child:
			stack.append(child)
			child = child.get_next()
	tree.queue_redraw()
