class_name Task extends RefCounted

enum TaskStatus {
	PENDING,
	RUNNING,
	DONE
}

class TaskAll extends RefCounted:
	var tasks: Dictionary[int, Task] = {}
	var results: Dictionary[int, Variant] = {}
	var status: TaskStatus = TaskStatus.PENDING

	signal done(results: Dictionary[int, Variant])

	func _init(t: Array[Task]) -> void:
		var id: int = 0
		for task: Task in t:
			tasks[id] = task
			task.done.connect(self._on_task_done.bind(id))
			id += 1

	func run() -> Array[Variant]:
		if self.status == TaskStatus.RUNNING:
			return await self.done
		if self.status == TaskStatus.DONE:
			return self.results.values()

		self.status = TaskStatus.RUNNING

		for task: Task in self.tasks.values():
			task.run()

		return await self.done

	func _on_task_done(id: int, result: Variant) -> void:
		self.results[id] = result
		if self.results.size() == self.tasks.size():
			self.status = TaskStatus.DONE
			self.done.emit()

class TaskAny extends RefCounted:
	var tasks: Dictionary[int, Task] = {}
	var result: Variant
	var status: TaskStatus = TaskStatus.PENDING

	signal done(result: Variant)

	func _init(t: Array[Task]) -> void:
		var id: int = 0
		for task: Task in t:
			tasks[id] = task
			task.done.connect(self._on_task_done.bind(id))
			id += 1

	func run() -> Array[Variant]:
		if self.status == TaskStatus.RUNNING:
			return await self.done
		if self.status == TaskStatus.DONE:
			return self.result

		self.status = TaskStatus.RUNNING

		for task: Task in self.tasks.values():
			task.run()

		return await self.done

	func _on_task_done(_id: int, res: Variant) -> void:
		if self.status == TaskStatus.RUNNING:
			self.result = res
			self.status = TaskStatus.DONE
			self.done.emit()


var task: Variant
var status: TaskStatus = TaskStatus.PENDING
var result: Variant = null

signal done(result: Variant)

static func all(tasks: Array[Variant]) -> TaskAll:
	var res: Array[Task] = []
	for t: Variant in tasks:
		res.push_back(Task.new(t))
	return TaskAll.new(res)

static func any(tasks: Array[Variant]) -> TaskAny:
	var res: Array[Task] = []
	for t: Variant in tasks:
		res.push_back(Task.new(t))
	return TaskAny.new(res)

func _init(t: Variant) -> void:
	assert(t is Signal || t is Callable)
	self.task = t

func run() -> Variant:
	if self.status == TaskStatus.DONE:
		return self.result
	elif self.status == TaskStatus.RUNNING:
		return await self.done

	self.status = TaskStatus.RUNNING
	if self.task is Signal:
		self.result = await (self.task as Signal)
	elif self.task is Callable:
		self.result = await (self.task as Callable).call()
	else:
		assert(false, "Task.task is neither Signal nor Callable")

	return self.result
