;; queue of threads
(module $queue

  (type $ft (func))
  (type $ct (cont $ft))

  ;; Table as simple queue (keeping it simple, no ring buffer)
  (table $task_queue 0 (ref null $ct))
  (global $qdelta i32 (i32.const 10))
  (global $qback (mut i32) (i32.const 0))
  (global $qfront (mut i32) (i32.const 0))

  (func $queue_empty (export "queue-empty") (result i32)
    (i32.eq (global.get $qfront) (global.get $qback))
  )

  (func $queue_count (export "queue-count") (result i32)
    (i32.sub (global.get $qback) (global.get $qfront))
  )

  (func $dequeue (export "dequeue") (result (ref null $ct))
    (local $i i32)
    (if (call $queue_empty)
      (then (return (ref.null $ct)))
    )
    (local.set $i (global.get $qfront))
    (global.set $qfront (i32.add (local.get $i) (i32.const 1)))
    (table.get $task_queue (local.get $i))
  )

  (func $enqueue (export "enqueue") (param $k (ref null $ct))
    ;; Check if queue is full
    (if (i32.eq (global.get $qback) (table.size $task_queue))
      (then
        ;; Check if there is enough space in the front to compact
        (if (i32.lt_u (global.get $qfront) (global.get $qdelta))
          (then
            ;; Space is below threshold, grow table instead
            (drop (table.grow $task_queue (ref.null $ct) (global.get $qdelta)))
          )
          (else
            ;; Enough space, move entries up to head of table
            (global.set $qback (i32.sub (global.get $qback) (global.get $qfront)))
            (table.copy $task_queue $task_queue
              (i32.const 0)         ;; dest = new front = 0
              (global.get $qfront)  ;; src = old front
              (global.get $qback)   ;; len = new back = old back - old front
            )
            (table.fill $task_queue      ;; null out old entries to avoid leaks
              (global.get $qback)   ;; start = new back
              (ref.null $ct)      ;; init value
              (global.get $qfront)  ;; len = old front = old front - new front
            )
            (global.set $qfront (i32.const 0))
          )
        )
      )
    )
    (table.set $task_queue (global.get $qback) (local.get $k))
    (global.set $qback (i32.add (global.get $qback) (i32.const 1)))
  )
)
(register "queue")

(module $scheduler-suspend
  (type $ft (func))
  ;; Continuation type of all tasks
  (type $ct (cont $ft))


  (func $task_enqueue (import "queue" "enqueue") (param (ref null $ct)))
  (func $task_dequeue (import "queue" "dequeue") (result (ref null $ct)))
  (func $task_queue-empty (import "queue" "queue-empty") (result i32))
  (func $task_queue-count (import "queue" "queue-count") (result i32))
  (func $print_i32 (import "spectest" "print_i32") (param i32))

  ;; Tag used to yield execution in one task and resume another one.
  (tag $yield)
  ;; Tag used to abort execution of a task.
  (tag $abort)

  (func $schedule_task (param $c (ref null $ct))
    ;; If the task queue is too long, cancel a task in the queue
    (if (i32.ge_s (call $task_queue-count) (i32.const 2))
      (then
        (block $h
          (try_table (catch $abort $h) (resume_throw $ct $abort (call $task_dequeue))))))
    (call $task_enqueue (local.get $c))
  )

  ;; Entry point, becomes parent of all tasks.
  ;; Also acts as scheduler when tasks yield or finish.
  (func $entry (param $initial_task (ref $ft))
    (local $next_task (ref null $ct))

    ;; initialise $task_queue with initial task
    (call $schedule_task (cont.new $ct (local.get $initial_task)))

    (loop $resume_next
      ;; pick $next_task from queue, or return if no more tasks.
      (if (call $task_queue-empty)
        (then (return))
        (else (local.set $next_task (call $task_dequeue)))
      )
      (block $on_yield (result (ref $ct))
        (resume $ct (on $yield $on_yield) (local.get $next_task))
        ;; task finished execution
        (br $resume_next)
      )
      ;; task suspended: put continuation in queue, then loop to determine next
      ;; one to resume.
      (call $schedule_task)
      (br $resume_next)
    )
  )

  ;; The function type and continuation type of $task_impl.
  (type $ft_task (func (param i32) (param i32)))
  (type $ct_task (cont $ft_task))

  ;; All tasks execute this function. Each task has an $id, but this is
  ;; only used for printing.
  ;; If $id < $max_id, then this function will add a task with
  ;; $id = $id+1 to the task queue.
  (elem declare func $task_impl)
  (func $task_impl
        (param $id i32)
        (param $max_id i32)

    (if (i32.lt_s (local.get $id) (local.get $max_id))
      (then
        ;; Create a new task with $id = $id+1
        (cont.bind $ct_task $ct
          (i32.add (local.get $id) (i32.const 1))
          (local.get $max_id)
          (cont.new $ct_task (ref.func $task_impl)))
        (call $schedule_task)
      )
    )

    (call $print_i32 (local.get $id))
    (suspend $yield)
    (call $print_i32 (local.get $id))
    (suspend $yield)
    (call $print_i32 (local.get $id))
  )

  ;; The actual $task_0 function simply call $task_impl, with 0 as the value
  ;; for $id, and 3 as the value for $max_id.

  (func $task_0
    (call $task_impl (i32.const 0) (i32.const 3))
  )
  (elem declare func $task_0)

  (func (export "main")
    (call $entry (ref.func $task_0))
  )
)
(invoke "main")
