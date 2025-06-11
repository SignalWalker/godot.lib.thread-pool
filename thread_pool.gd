class_name ThreadPool extends RefCounted

class TaskResult extends RefCounted:
	static var _PENDING: RefCounted = RefCounted.new()

	var result_semaphore: Semaphore = Semaphore.new()
	var result_mutex: Mutex = Mutex.new()
	var result: Variant = _PENDING

	var _emitted_ready: bool = false;

	signal ready()

	func is_pending() -> bool:
		self.result_mutex.lock()
		var res: bool = self.result == _PENDING
		self.result_mutex.unlock()
		return res

	func get_result() -> Variant:
		self.result_mutex.lock()
		var res: Variant = self.result
		self.result_mutex.unlock()
		return res

	func get_result_blocking() -> Variant:
		self.result_semaphore.wait()
		self.result_mutex.lock()
		var res: Variant = self.result
		self.result_mutex.unlock()
		return res

	func get_result_async() -> Variant:
		if !self._emitted_ready:
			await self.ready
		var res: Variant = self.get_result()
		# debug assertion
		assert(res != _PENDING, "TaskResult has emitted ready despite result == _PENDING")
		return res

	func _emit_ready() -> void:
		self._emitted_ready = true
		self.ready.emit()

	func _finish(res: Variant) -> void:
		self.result_mutex.lock()
		if self.result != _PENDING:
			printerr("called TaskResult._finish() on already-finished task")
		self.result = res
		self.result_mutex.unlock()
		self.result_semaphore.post()
		# queue `_emit_ready` to be called on the main thread
		self._emit_ready.call_deferred()

class QueuedTask extends RefCounted:
	var result: TaskResult = TaskResult.new()
	var work: Callable
	func _init(w: Callable) -> void:
		self.work = w
	func run() -> void:
		self.result._finish(self.work.call())

static func _pool_thread_fn(q_sem: Semaphore, q_mut: Mutex, done: Array[bool], q: Array[QueuedTask]) -> void:
	while true:
		q_sem.wait()
		q_mut.lock()
		var is_done: bool = done[0]
		var task: QueuedTask = q.pop_front()
		q_mut.unlock()
		if is_done:
			break
		if task != null:
			task.run()

var queue_semaphore: Semaphore
var queue_mutex: Mutex
var done_flag: Array[bool] = [false]
var pool: Array[Thread]
var work_queue: Array[QueuedTask] = []

func _init(amt: int, priority: int = 1) -> void:
	self.queue_semaphore = Semaphore.new()
	self.queue_mutex = Mutex.new()
	for i in range(amt):
		var thread: Thread = Thread.new()
		var start_res: Error = thread.start(_pool_thread_fn.bind(self.queue_semaphore, self.queue_mutex, self.done_flag, self.work_queue), priority)
		assert(start_res == OK, "could not start ThreadPool thread")
		pool.push_back(thread)

func stop() -> void:
	self.queue_mutex.lock()
	self.done_flag[0] = true
	self.queue_mutex.unlock()
	self.queue_semaphore.post(self.pool.size())
	for t: Thread in self.pool:
		t.wait_to_finish()

func enqueue(work: Callable) -> TaskResult:
	var task: QueuedTask = QueuedTask.new(work)
	var res: TaskResult = task.result
	self.queue_mutex.lock()
	self.work_queue.push_back(task)
	self.queue_mutex.unlock()
	self.queue_semaphore.post()
	return res
