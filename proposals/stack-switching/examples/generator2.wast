(module $generator
  (type $ft0 (func))
  (type $ft1 (func (param i32)))
  ;; Types of continuations used by the generator:
  ;; No param or result types for $ct0: $generator function has no
  ;; parameters or return values.
  (type $ct0 (cont $ft0))
  ;; One param of type i32 for $ct1: An i32 is passed back to the
  ;; generator when resuming it, and $generator function has no return
  ;; values.
  (type $ct1 (cont $ft1))

  (func $print (import "spectest" "print_i32") (param i32))

  ;; Tag used to coordinate between generator and consumer: The i32
  ;; param corresponds to the generated values passed to consumer, and
  ;; the i32 result corresponds to the value passed from the consumer
  ;; back to the generator.
  (tag $yield (param i32) (result i32))

  ;; Simple counter yielding increasing values from 0, resetting when
  ;; a nonzero i32 is passed back.
  (func $generator
    (local $count i32)
    (local.set $count (i32.const 0))
    (loop $loop
      ;; Suspend execution, pass current value of $count to consumer
      (suspend $yield (local.get $count))
      ;; Returned from consumer, stack now contains an i32 passed back
      (if
        (then (local.set $count (i32.const 0)))
        (else (local.set $count (i32.add (local.get $count) (i32.const 1))))
      )
      (br $loop)
    )
  )
  (elem declare func $generator)

  (func $consumer (export "consumer")
    ;; The continuation of the generator
    (local $c0 (ref $ct0))
    ;; For temporarily storing the suspended generator, as there is no
    ;; stack duplication instructions in wasm.
    (local $c1 (ref $ct1))
    (local $i i32)
    ;; Create continuation executing function $generator.
    ;; Execution only starts when resumed for the first time.
    (local.set $c0 (cont.new $ct0 (ref.func $generator)))
    (local.set $i (i32.const 10))

    (loop $loop
      (block $on_yield (result i32 (ref $ct1))
        ;; Resume continuation $c0
        (resume $ct0 (on $yield $on_yield) (local.get $c0))
        ;; $generator returned: no more data
        (return)
      )
      ;; Generator suspended, stack now contains [i32 (ref $ct0)]
      ;; Save continuation to resume it in next iteration
      (local.set $c1)
      ;; Stack now contains the i32 value yielded by $generator
      (call $print)

      ;; reset after 5 rounds
      (cont.bind $ct1 $ct0 (i32.eq (local.get $i) (i32.const 6)) (local.get $c1))
      (local.set $c0)

      (local.tee $i (i32.sub (local.get $i) (i32.const 1)))
      (br_if $loop)
    )
  )

)

(invoke "consumer")
