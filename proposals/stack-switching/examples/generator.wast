(module $generator
  (type $ft (func))
  (type $ft1 (func (param i32)))
  ;; TODO: update comment here
  ;; Types of continuations used by the generator:
  ;; No need for param or result types: No data data passed back to the
  ;; generator when resuming it, and $generator function has no return
  ;; values.
  (type $ct (cont $ft))
  (type $ct1 (cont $ft1))

  (func $print (import "spectest" "print_i32") (param i32))

  ;; TODO: update comment here
  ;; Tag used to coordinate between generator and consumer: The i32 param
  ;; corresponds to the generated values passed; no values passed back from
  ;; generator to consumer.
  (tag $yield (param i32) (result i32))
  (tag $exn (param i32))

  ;; TODO: update comment here
  ;; Simple generator yielding values from 100 down to 1
  (func $generator
    (local $sum i32)
    (local.set $sum (i32.const 1))
    (loop $l
      ;; TODO: update comment here
      ;; Suspend execution, pass current value of $i to consumer
      (suspend $yield (local.get $sum))
      ;; stack: i32 from yield
      (i32.add (local.get $sum))
      (local.tee $sum)
      (i32.le_s (i32.const 500))
      (br_if $l)
    )
  )
  (elem declare func $generator)

  (func $consumer (export "consumer")
    (local $c (ref $ct))
    ;; for temporarily storing the result continuation, given there's no stack duplication/juggling facilities in wasm
    (local $c1 (ref $ct1))
    (local $res i32)
    ;; TODO: update comment here
    ;; Create continuation executing function $generator.
    ;; Execution only starts when resumed for the first time.
    (local.set $c (cont.new $ct (ref.func $generator)))

    (loop $loop
      (block $on_yield (result i32 (ref $ct1))
        ;; Resume continuation $c
        (resume $ct (on $yield $on_yield) (local.get $c))
        ;; $generator returned: no more data
        (return)
      )
      ;; TODO: update comment here
      ;; Generator suspended, stack now contains [i32 (ref $ct)]
      ;; Save continuation to resume it in next iteration
      (local.set $c1)
      (local.tee $res)
      ;; TODO: update comment here
      ;; Stack now contains the i32 value yielded by $generator
      (call $print)

      (cont.bind $ct1 $ct (local.get $res) (local.get $c1))
      (local.set $c)

      (i32.le_s (local.get $res) (i32.const 100))
      (br_if $loop)

      (resume_throw $ct $exn (local.get $res) (local.get $c))
    )
  )

)

(invoke "consumer")
